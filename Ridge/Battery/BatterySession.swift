import Combine
import Foundation

/// 外设电量会话：合并 IOBluetooth / IOHID / BLE / system_profiler，驱动控制台与告警。
@MainActor
final class BatterySession: ObservableObject {
    static let shared = BatterySession()

    @Published private(set) var devices: [BatteryDevice] = []

    private let settings = BatterySettings.shared
    private var timer: Timer?
    private var started = false
    private var lowAlertArmed: Set<String> = []
    private var fullAlertArmed: Set<String> = []
    private var isRefreshing = false

    private init() {}

    func start() {
        guard !started else {
            refresh(reason: "resume")
            return
        }
        started = true
        BatteryCoreBluetoothMonitor.shared.start()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "tick")
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        refresh(reason: "start")
        AppLog.info("Battery", "电量会话已启动")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
        devices = []
        BatteryCoreBluetoothMonitor.shared.stop()
        AppLog.info("Battery", "电量会话已停止")
    }

    func refresh(reason: String) {
        guard !isRefreshing else { return }
        isRefreshing = true

        if reason != "bleUpdate" {
            BatteryCoreBluetoothMonitor.shared.requestRefresh(reason: reason)
        }

        let bluetooth = BatteryBluetoothProbe.connectedDevices()
        let hid = BatteryHIDProbe.connectedDevices()
        let bleLevels = BatteryCoreBluetoothMonitor.shared.levelsByName
        let threshold = settings.lowThresholdPercent
        let forceProfiler = reason == "start"
            || reason == "tick"
            || reason == "deckAppear"
            || reason == "batteryConfigAppear"
            || reason == "resume"

        // 先用缓存 / 空 profiler 快速上屏，避免 system_profiler 卡住主线程。
        let cachedProfiler = BatterySystemProfilerProbe.connectedDevices(force: false)
        applyMerged(
            bluetooth: bluetooth,
            hid: hid,
            profiler: cachedProfiler,
            bleLevels: bleLevels,
            threshold: threshold,
            reason: reason
        )

        guard forceProfiler else {
            isRefreshing = false
            return
        }

        Task { [weak self] in
            let profiler = await Task.detached(priority: .utility) {
                BatterySystemProfilerProbe.connectedDevices(force: true)
            }.value
            await MainActor.run {
                defer { self?.isRefreshing = false }
                guard let self else { return }
                // 异步回来时重新采一次即时源，避免长时间 profiler 期间漏掉刚连上的设备。
                self.applyMerged(
                    bluetooth: BatteryBluetoothProbe.connectedDevices(),
                    hid: BatteryHIDProbe.connectedDevices(),
                    profiler: profiler,
                    bleLevels: BatteryCoreBluetoothMonitor.shared.levelsByName,
                    threshold: threshold,
                    reason: reason + "+profiler"
                )
            }
        }
    }

    private func applyMerged(
        bluetooth: [BatteryBluetoothProbe.Snapshot],
        hid: [BatteryHIDProbe.Snapshot],
        profiler: [BatterySystemProfilerProbe.Snapshot],
        bleLevels: [String: Int],
        threshold: Int,
        reason: String
    ) {
        let mapped = Self.mergeDevices(
            bluetooth: bluetooth,
            hid: hid,
            profiler: profiler,
            bleLevels: bleLevels,
            threshold: threshold
        )
        if mapped != devices {
            devices = mapped
            AppLog.info("Battery", "外设电量已刷新", [
                "reason": reason,
                "count": mapped.count,
                "withBattery": mapped.filter(\.hasBatteryReading).count,
                "withListening": mapped.filter { $0.listeningMode != nil }.count,
                "names": mapped.map(\.name).joined(separator: ",")
            ])
        }
        evaluateAlerts(mapped)
    }

    /// 合并多路数据。已连接但无电量（如部分 Sony 耳机）仍展示。
    private static func mergeDevices(
        bluetooth: [BatteryBluetoothProbe.Snapshot],
        hid: [BatteryHIDProbe.Snapshot],
        profiler: [BatterySystemProfilerProbe.Snapshot],
        bleLevels: [String: Int],
        threshold: Int
    ) -> [BatteryDevice] {
        var byAddress: [String: BatteryDevice] = [:]
        var byName: [String: String] = [:]

        func upsert(
            id: String,
            name: String,
            kind: BatteryDeviceKind,
            percent: Int?,
            charging: Bool,
            left: Int?,
            right: Int?,
            casePct: Int?,
            listeningMode: BatteryListeningMode? = nil
        ) {
            let nameKey = normalizeName(name)
            let existing = byAddress[id] ?? byName[nameKey].flatMap { byAddress[$0] }
            let mergedPercent = percent
                ?? existing?.percent
                ?? bleLevels[nameKey]
                ?? hid.first(where: { normalizeName($0.name) == nameKey })?.percent
            let mergedLeft = left ?? existing?.leftPercent
            let mergedRight = right ?? existing?.rightPercent
            let mergedCase = casePct ?? existing?.casePercent
            let mergedListening = listeningMode ?? existing?.listeningMode
            var mergedKind = kind
            if mergedKind == .other {
                mergedKind = existing?.kind
                    ?? BatteryBluetoothProbe.classifyPublic(
                        name: name,
                        hasSplitBuds: mergedLeft != nil || mergedRight != nil
                    )
            }
            let low = mergedPercent.map { !charging && $0 <= threshold } ?? false
            let device = BatteryDevice(
                id: existing?.id ?? id,
                name: name,
                kind: mergedKind,
                percent: mergedPercent,
                isCharging: charging || (existing?.isCharging ?? false),
                isLow: low,
                leftPercent: mergedLeft,
                rightPercent: mergedRight,
                casePercent: mergedCase,
                listeningMode: mergedListening,
                subtitle: subtitle(
                    percent: mergedPercent,
                    charging: charging,
                    low: low,
                    listeningMode: mergedListening
                )
            )
            byAddress[device.id] = device
            byName[nameKey] = device.id
        }

        // 1) system_profiler：与设置「我的设备」对齐，含无电量条目。
        for snap in profiler {
            upsert(
                id: snap.address,
                name: snap.name,
                kind: snap.kind,
                percent: snap.percent,
                charging: false,
                left: snap.leftPercent,
                right: snap.rightPercent,
                casePct: snap.casePercent
            )
        }

        // 2) IOBluetooth：补充电量私有字段 / 充电态 / 聆听模式。
        for snap in bluetooth {
            upsert(
                id: snap.address,
                name: snap.name,
                kind: snap.kind,
                percent: snap.percent,
                charging: snap.isCharging,
                left: snap.leftPercent,
                right: snap.rightPercent,
                casePct: snap.casePercent,
                listeningMode: snap.listeningMode
            )
        }

        // 3) HID BatteryPercent
        for snap in hid {
            let nameKey = normalizeName(snap.name)
            if let id = byName[nameKey] {
                upsert(
                    id: id,
                    name: snap.name,
                    kind: snap.kind,
                    percent: snap.percent,
                    charging: false,
                    left: nil,
                    right: nil,
                    casePct: nil
                )
            } else {
                upsert(
                    id: "hid.\(nameKey)",
                    name: snap.name,
                    kind: snap.kind,
                    percent: snap.percent,
                    charging: false,
                    left: nil,
                    right: nil,
                    casePct: nil
                )
            }
        }

        // 4) BLE Battery Service 按名回填
        for (nameKey, percent) in bleLevels {
            if let id = byName[nameKey], var device = byAddress[id] {
                if device.percent == nil {
                    device.percent = percent
                    device.isLow = percent <= threshold
                    device.subtitle = subtitle(
                        percent: percent,
                        charging: device.isCharging,
                        low: device.isLow,
                        listeningMode: device.listeningMode
                    )
                    byAddress[id] = device
                }
            }
        }

        return byAddress.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func subtitle(
        percent: Int?,
        charging: Bool,
        low: Bool,
        listeningMode: BatteryListeningMode?
    ) -> String {
        if charging { return L10n.Battery.statusCharging }
        if low { return L10n.Battery.statusCritical }
        if let listeningMode {
            return L10n.Battery.listeningModeTitle(listeningMode)
        }
        guard let percent else { return L10n.Battery.statusConnected }
        if percent >= 50 { return L10n.Battery.statusHealthy }
        return L10n.Battery.statusModerate
    }

    func snoozeLowAlert(deviceID: String) {
        settings.snoozeLowAlert(deviceID: deviceID, minutes: 30)
        lowAlertArmed.remove(deviceID)
        IslandNoticeCenter.shared.dismiss()
        AppLog.info("Battery", "已稍后提醒并收起低电通知", [
            "device": deviceID.prefix(12).description
        ])
    }

    private func evaluateAlerts(_ devices: [BatteryDevice]) {
        let threshold = settings.lowThresholdPercent
        let liveIDs = Set(devices.map(\.id))

        for id in lowAlertArmed where !liveIDs.contains(id) {
            lowAlertArmed.remove(id)
        }
        for id in fullAlertArmed where !liveIDs.contains(id) {
            fullAlertArmed.remove(id)
        }

        for device in devices {
            guard let percent = device.percent else { continue }

            if percent > threshold + 5 {
                lowAlertArmed.remove(device.id)
                settings.clearSnooze(deviceID: device.id)
            }
            if percent < 100 {
                fullAlertArmed.remove(device.id)
            }

            if settings.lowAlertEnabled,
               device.isLow,
               !lowAlertArmed.contains(device.id),
               !settings.isLowSnoozed(deviceID: device.id)
            {
                lowAlertArmed.insert(device.id)
                let notice = BatteryPeripheralNotice(
                    id: "battery.low.\(device.id).\(percent)",
                    deviceID: device.id,
                    deviceName: device.name,
                    kind: device.kind,
                    percent: percent,
                    threshold: threshold,
                    detail: L10n.Battery.lowNoticeDetail(percent, threshold)
                )
                IslandNoticeCenter.shared.present(.peripheralLowBattery(notice))
                AppLog.info("Battery", "已投递低电通知", [
                    "name": device.name,
                    "percent": percent,
                    "threshold": threshold
                ])
            }

            if settings.fullChargeAlertEnabled,
               percent >= 100,
               !fullAlertArmed.contains(device.id)
            {
                fullAlertArmed.insert(device.id)
                let notice = BatteryPeripheralNotice(
                    id: "battery.full.\(device.id)",
                    deviceID: device.id,
                    deviceName: device.name,
                    kind: device.kind,
                    percent: percent,
                    threshold: 100,
                    detail: L10n.Battery.fullNoticeDetail
                )
                IslandNoticeCenter.shared.present(.peripheralFullCharge(notice))
                AppLog.info("Battery", "已投递满电通知", ["name": device.name])
            }
        }
    }
}
