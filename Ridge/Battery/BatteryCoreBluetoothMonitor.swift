import CoreBluetooth
import Foundation

/// 经 BLE Battery Service（0x180F / 0x2A19）读取电量。
/// - 已连接外设：第三方键盘等走 `retrieveConnectedPeripherals`
/// - Continuity：iPhone / iPad / Watch 常在「未连接」态仍广播 Nearby Info（Apple mfg type 0x10），
///   需主动扫描并短暂连接 Battery Service（与系统控制中心 Continuity 电量同源思路）
@MainActor
final class BatteryCoreBluetoothMonitor: NSObject, ObservableObject {
    static let shared = BatteryCoreBluetoothMonitor()

    struct ContinuitySnapshot: Equatable {
        var id: String
        var name: String
        var kind: BatteryDeviceKind
        var percent: Int
        var isCharging: Bool
        var lastSeen: Date
    }

    /// 规范化设备名 → 电量 1…100（回填已连接外设）。
    @Published private(set) var levelsByName: [String: Int] = [:]
    /// Continuity 近场苹果设备（可独立成卡，不必先有 IOBluetooth 条目）。
    @Published private(set) var continuityDevices: [ContinuitySnapshot] = []

    private var central: CBCentralManager?
    private var held: [UUID: CBPeripheral] = [:]
    private var pendingIDs: Set<UUID> = []
    private var continuityPending: Set<UUID> = []
    private var continuityByUUID: [UUID: ContinuitySnapshot] = [:]
    private var previousContinuityPercent: [String: Int] = [:]
    private var started = false
    private var isScanningContinuity = false
    private var scanStopWork: DispatchWorkItem?
    private var lastContinuityScanAt: Date = .distantPast

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")
    private let hidService = CBUUID(string: "1812")
    private let deviceInfoService = CBUUID(string: "180A")

    /// Continuity 扫描最短间隔，避免刷屏占射频。
    private let continuityScanMinInterval: TimeInterval = 20
    private let continuityScanDuration: TimeInterval = 10
    /// 超过此时长未见广播则从列表摘掉。
    private let continuityStaleAfter: TimeInterval = 180

    private override init() {
        super.init()
    }

    func start() {
        guard !started else {
            requestRefresh(reason: "resume")
            return
        }
        started = true
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
        AppLog.info("Battery", "CoreBluetooth 电量监视已启动")
    }

    func stop() {
        scanStopWork?.cancel()
        scanStopWork = nil
        if isScanningContinuity {
            central?.stopScan()
            isScanningContinuity = false
        }
        for id in continuityPending {
            if let peripheral = held[id] {
                central?.cancelPeripheralConnection(peripheral)
            }
        }
        started = false
        held.removeAll()
        pendingIDs.removeAll()
        continuityPending.removeAll()
        continuityByUUID.removeAll()
        previousContinuityPercent.removeAll()
        levelsByName = [:]
        continuityDevices = []
        central = nil
        AppLog.info("Battery", "CoreBluetooth 电量监视已停止")
    }

    func requestRefresh(reason: String) {
        pruneStaleContinuity()
        guard let central, central.state == .poweredOn else {
            AppLog.debug("Battery", "BLE 电量刷新跳过：未就绪", [
                "reason": reason,
                "state": central?.state.rawValue ?? -1
            ])
            return
        }
        refreshConnectedPeripherals(reason: reason)
        startContinuityScanIfNeeded(reason: reason)
    }

    // MARK: - Connected peripherals (keyboards etc.)

    private func refreshConnectedPeripherals(reason: String) {
        guard let central else { return }
        let list = central.retrieveConnectedPeripherals(withServices: [batteryService, hidService])
        var seen = Set<UUID>()
        var uniq: [CBPeripheral] = []
        for p in list where seen.insert(p.identifier).inserted {
            uniq.append(p)
        }
        AppLog.debug("Battery", "BLE 已连接外设", [
            "reason": reason,
            "count": uniq.count
        ])
        guard !uniq.isEmpty else { return }

        pendingIDs = Set(uniq.map(\.identifier))
        for peripheral in uniq {
            held[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state == .connected {
                peripheral.discoverServices([batteryService])
            } else {
                central.connect(peripheral, options: nil)
            }
        }
    }

    // MARK: - Continuity (iPhone / iPad / Watch)

    private func startContinuityScanIfNeeded(reason: String) {
        guard let central else { return }
        guard !isScanningContinuity else { return }
        let since = Date().timeIntervalSince(lastContinuityScanAt)
        // start / 配置页 / 控制台出现时强制扫；tick 受最小间隔限制。
        let force = reason == "start"
            || reason == "resume"
            || reason == "poweredOn"
            || reason == "deckAppear"
            || reason == "batteryConfigAppear"
        if !force, since < continuityScanMinInterval {
            return
        }
        lastContinuityScanAt = Date()
        isScanningContinuity = true
        AppLog.info("Battery", "开始 Continuity BLE 扫描", [
            "reason": reason,
            "duration": Int(continuityScanDuration)
        ])
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanStopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stopContinuityScan()
        }
        scanStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + continuityScanDuration, execute: work)
    }

    private func stopContinuityScan() {
        guard isScanningContinuity else { return }
        isScanningContinuity = false
        central?.stopScan()
        AppLog.debug("Battery", "Continuity BLE 扫描结束", [
            "devices": continuityDevices.count,
            "pending": continuityPending.count
        ])
    }

    private func isContinuityAppleCandidate(_ name: String) -> Bool {
        let hay = name.lowercased()
        return hay.contains("iphone")
            || hay.contains("ipad")
            || hay.contains("watch")
            || hay.contains("手机")
            || hay.contains("手表")
    }

    private func continuityKind(for name: String) -> BatteryDeviceKind {
        let hay = name.lowercased()
        if hay.contains("ipad") { return .tablet }
        if hay.contains("watch") || hay.contains("手表") { return .watch }
        return .phone
    }

    /// Apple Continuity manufacturer data：company 0x004C，type 0x10 Nearby Info / 0x0C Handoff。
    private func isContinuityAdvertisement(_ data: Data) -> Bool {
        guard data.count > 2 else { return false }
        guard data[0] == 0x4C, data[1] == 0x00 else { return false }
        let type = data[2]
        return type == 0x10 || type == 0x0C
    }

    private func shouldConnectContinuity(named name: String) -> Bool {
        let key = Self.normalizeName(name)
        if let snap = continuityDevices.first(where: { Self.normalizeName($0.name) == key }) {
            // 90s 内已有读数则本轮不重连，减轻射频占用。
            return Date().timeIntervalSince(snap.lastSeen) > 90
        }
        return true
    }

    private func pruneStaleContinuity() {
        let cutoff = Date().addingTimeInterval(-continuityStaleAfter)
        let before = continuityByUUID.count
        continuityByUUID = continuityByUUID.filter { $0.value.lastSeen >= cutoff }
        if continuityByUUID.count != before {
            publishContinuity()
            AppLog.info("Battery", "已摘除过期 Continuity 设备", [
                "removed": before - continuityByUUID.count,
                "remain": continuityByUUID.count
            ])
        }
    }

    private func publishContinuity() {
        continuityDevices = continuityByUUID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func finishConnected(_ id: UUID) {
        guard pendingIDs.remove(id) != nil else { return }
        if pendingIDs.isEmpty, continuityPending.isEmpty {
            BatterySession.shared.refresh(reason: "bleUpdate")
        }
    }

    private func finishContinuity(_ id: UUID, disconnect: Bool) {
        continuityPending.remove(id)
        if disconnect, let peripheral = held[id], let central {
            central.cancelPeripheralConnection(peripheral)
        }
        if pendingIDs.isEmpty, continuityPending.isEmpty {
            BatterySession.shared.refresh(reason: "continuityBLE")
        }
    }

    private static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension BatteryCoreBluetoothMonitor: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            AppLog.debug("Battery", "CBCentral 状态", ["state": central.state.rawValue])
            if central.state == .poweredOn {
                self.requestRefresh(reason: "poweredOn")
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard let name = peripheral.name?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                self.isContinuityAppleCandidate(name)
            else { return }
            guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                  self.isContinuityAdvertisement(mfg)
            else { return }
            guard self.shouldConnectContinuity(named: name) else { return }
            guard self.continuityPending.insert(peripheral.identifier).inserted else { return }

            self.held[peripheral.identifier] = peripheral
            peripheral.delegate = self
            AppLog.info("Battery", "发现 Continuity 设备，准备读取电量", [
                "name": name,
                "rssi": RSSI.intValue,
                "type": mfg.count > 2 ? Int(mfg[2]) : -1
            ])
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            let isContinuity = self.continuityPending.contains(peripheral.identifier)
            AppLog.debug("Battery", "BLE 已连接", [
                "name": peripheral.name ?? "",
                "continuity": isContinuity
            ])
            peripheral.discoverServices([self.batteryService, self.deviceInfoService])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            AppLog.warn("Battery", "BLE 连接失败", [
                "name": peripheral.name ?? "",
                "error": error?.localizedDescription ?? "",
                "continuity": self.continuityPending.contains(peripheral.identifier)
            ])
            if self.continuityPending.contains(peripheral.identifier) {
                self.finishContinuity(peripheral.identifier, disconnect: false)
            } else {
                self.finishConnected(peripheral.identifier)
            }
        }
    }
}

extension BatteryCoreBluetoothMonitor: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            let continuity = self.continuityPending.contains(peripheral.identifier)
            if let error {
                AppLog.debug("Battery", "BLE 发现服务失败", [
                    "name": peripheral.name ?? "",
                    "error": error.localizedDescription
                ])
                if continuity {
                    self.finishContinuity(peripheral.identifier, disconnect: true)
                } else {
                    self.finishConnected(peripheral.identifier)
                }
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == self.batteryService }) else {
                if continuity {
                    self.finishContinuity(peripheral.identifier, disconnect: true)
                } else {
                    self.finishConnected(peripheral.identifier)
                }
                return
            }
            peripheral.discoverCharacteristics([self.batteryLevel], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            let continuity = self.continuityPending.contains(peripheral.identifier)
            if let error {
                AppLog.debug("Battery", "BLE 发现特征失败", [
                    "name": peripheral.name ?? "",
                    "error": error.localizedDescription
                ])
                if continuity {
                    self.finishContinuity(peripheral.identifier, disconnect: true)
                } else {
                    self.finishConnected(peripheral.identifier)
                }
                return
            }
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == self.batteryLevel })
            else {
                if continuity {
                    self.finishContinuity(peripheral.identifier, disconnect: true)
                } else {
                    self.finishConnected(peripheral.identifier)
                }
                return
            }
            peripheral.readValue(for: characteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            let continuity = self.continuityPending.contains(peripheral.identifier)
            defer {
                if continuity {
                    self.finishContinuity(peripheral.identifier, disconnect: true)
                } else {
                    self.finishConnected(peripheral.identifier)
                }
            }
            if let error {
                AppLog.debug("Battery", "BLE 读电量失败", [
                    "name": peripheral.name ?? "",
                    "error": error.localizedDescription
                ])
                return
            }
            guard characteristic.uuid == self.batteryLevel,
                  let byte = characteristic.value?.first
            else { return }
            let percent = Int(byte)
            guard percent > 0, percent <= 100 else { return }
            let name = (peripheral.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let key = Self.normalizeName(name)
            let previous = self.levelsByName[key]
            self.levelsByName[key] = percent

            if continuity {
                let prior = self.previousContinuityPercent[key]
                let charging = (prior.map { percent > $0 } ?? false)
                self.previousContinuityPercent[key] = percent
                let snap = ContinuitySnapshot(
                    id: "continuity.\(peripheral.identifier.uuidString)",
                    name: name,
                    kind: self.continuityKind(for: name),
                    percent: percent,
                    isCharging: charging,
                    lastSeen: Date()
                )
                self.continuityByUUID[peripheral.identifier] = snap
                self.publishContinuity()
                AppLog.info("Battery", "Continuity 电量已更新", [
                    "name": name,
                    "percent": percent,
                    "charging": charging,
                    "kind": snap.kind.rawValue
                ])
            } else if previous != percent {
                AppLog.info("Battery", "BLE 电量已更新", [
                    "name": name,
                    "percent": percent
                ])
            }
        }
    }
}
