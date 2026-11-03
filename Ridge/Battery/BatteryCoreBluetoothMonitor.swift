import CoreBluetooth
import Foundation

/// 经 BLE Battery Service（0x180F / 0x2A19）读取电量。
/// 第三方键盘（如 R75）在 IOBluetooth 私有字段里常为 0，系统设置走的就是这条路径。
@MainActor
final class BatteryCoreBluetoothMonitor: NSObject, ObservableObject {
    static let shared = BatteryCoreBluetoothMonitor()

    /// 规范化设备名 → 电量 1…100。
    @Published private(set) var levelsByName: [String: Int] = [:]

    private var central: CBCentralManager?
    private var held: [UUID: CBPeripheral] = [:]
    private var pendingIDs: Set<UUID> = []
    private var started = false
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")
    private let hidService = CBUUID(string: "1812")

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
        started = false
        held.removeAll()
        levelsByName = [:]
        central = nil
        AppLog.info("Battery", "CoreBluetooth 电量监视已停止")
    }

    func requestRefresh(reason: String) {
        guard let central, central.state == .poweredOn else {
            AppLog.debug("Battery", "BLE 电量刷新跳过：未就绪", [
                "reason": reason,
                "state": central?.state.rawValue ?? -1
            ])
            return
        }
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

    private func finish(_ id: UUID) {
        guard pendingIDs.remove(id) != nil else { return }
        if pendingIDs.isEmpty {
            BatterySession.shared.refresh(reason: "bleUpdate")
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

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([self.batteryService])
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
                "error": error?.localizedDescription ?? ""
            ])
            self.finish(peripheral.identifier)
        }
    }
}

extension BatteryCoreBluetoothMonitor: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                AppLog.debug("Battery", "BLE 发现服务失败", [
                    "name": peripheral.name ?? "",
                    "error": error.localizedDescription
                ])
                self.finish(peripheral.identifier)
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == self.batteryService }) else {
                self.finish(peripheral.identifier)
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
            if let error {
                AppLog.debug("Battery", "BLE 发现特征失败", [
                    "name": peripheral.name ?? "",
                    "error": error.localizedDescription
                ])
                self.finish(peripheral.identifier)
                return
            }
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == self.batteryLevel })
            else {
                self.finish(peripheral.identifier)
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
            defer { self.finish(peripheral.identifier) }
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
            let name = (peripheral.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let key = Self.normalizeName(name)
            let previous = self.levelsByName[key]
            self.levelsByName[key] = percent
            if previous != percent {
                AppLog.info("Battery", "BLE 电量已更新", [
                    "name": name,
                    "percent": percent
                ])
            }
        }
    }
}
