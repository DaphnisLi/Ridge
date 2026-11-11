import Combine
import CoreAudio
import Foundation

/// 外设电量会话：合并 IOBluetooth / IOHID / BLE / Continuity / system_profiler，驱动控制台与告警。
@MainActor
final class BatterySession: ObservableObject {
    static let shared = BatterySession()

    @Published private(set) var devices: [BatteryDevice] = []

    private let settings = BatterySettings.shared
    private var timer: Timer?
    private var started = false
    private var lowAlertArmed: Set<String> = []
    private var fullAlertArmed: Set<String> = []
    /// 已见过的外设 id；首轮只播种不弹「接入」，之后出现新 id 才提示。
    private var knownDeviceIDs: Set<String> = []
    private var connectSeeded = false
    private var isRefreshing = false

    private init() {}

    /// 小组件库总开关：关则低电 / 满电 / 接入都不投递。
    private var isPeripheralTipEnabled: Bool {
        WidgetSettings.shared.isEnabled(PeripheralTipWidget.manifest.id)
    }

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
        LiveIslandGate.shared.close(LiveIslandGate.batteryID, reason: "sessionStop")
        BatteryCoreBluetoothMonitor.shared.stop()
        AppLog.info("Battery", "电量会话已停止")
    }

    func refresh(reason: String) {
        // Continuity / BLE 回调在 profiler 异步窗口内也必须立刻合并，否则会丢 iPhone 读数。
        // 勿再 requestRefresh，避免扫描回调里套扫描刷日志。
        if reason == "bleUpdate"
            || reason == "continuityBLE"
            || reason == "continuityDiscovered"
        {
            applyMerged(
                bluetooth: BatteryBluetoothProbe.connectedDevices(),
                hid: BatteryHIDProbe.connectedDevices(),
                profiler: BatterySystemProfilerProbe.connectedDevices(force: false),
                bleLevels: BatteryCoreBluetoothMonitor.shared.levelsByName,
                continuity: BatteryCoreBluetoothMonitor.shared.continuityDevices,
                threshold: settings.lowThresholdPercent,
                reason: reason
            )
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true

        BatteryCoreBluetoothMonitor.shared.requestRefresh(reason: reason)

        let bluetooth = BatteryBluetoothProbe.connectedDevices()
        let hid = BatteryHIDProbe.connectedDevices()
        let bleLevels = BatteryCoreBluetoothMonitor.shared.levelsByName
        let continuity = BatteryCoreBluetoothMonitor.shared.continuityDevices
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
            continuity: continuity,
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
                    continuity: BatteryCoreBluetoothMonitor.shared.continuityDevices,
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
        continuity: [BatteryCoreBluetoothMonitor.ContinuitySnapshot],
        threshold: Int,
        reason: String
    ) {
        let mapped = Self.mergeDevices(
            bluetooth: bluetooth,
            hid: hid,
            profiler: profiler,
            bleLevels: bleLevels,
            continuity: continuity,
            threshold: threshold
        )
        if mapped != devices {
            devices = mapped
            AppLog.info("Battery", "外设电量已刷新", [
                "reason": reason,
                "count": mapped.count,
                "withBattery": mapped.filter(\.hasBatteryReading).count,
                "withListening": mapped.filter { $0.listeningMode != nil }.count,
                "continuity": continuity.count,
                "names": mapped.map(\.name).joined(separator: ",")
            ])
        }
        evaluateAlerts(mapped)
        refreshLivePresence(reason: reason)
    }

    /// 有外设且模块开启 → 直接准入电量页；无设备则撤常驻。不再投「打开」邀请 tip。
    func refreshLivePresence(reason: String) {
        let batteryID = LiveIslandGate.batteryID
        // 勿在 ControlDeckSettings 尚处 static init 时同步回访 shared（会 dispatch_once 重入崩）。
        guard ControlDeckSettings.shared.isModuleEnabled("battery") else {
            LiveIslandGate.shared.close(batteryID, reason: "moduleOff:\(reason)")
            return
        }
        guard !devices.isEmpty else {
            LiveIslandGate.shared.close(batteryID, reason: "noDevices:\(reason)")
            return
        }
        LiveIslandGate.shared.admit(batteryID, reason: reason)
    }

    /// 兼容旧调用名。
    func refreshLiveInvite(reason: String) {
        refreshLivePresence(reason: reason)
    }

    /// 合并多路数据。已连接但无电量（如部分 Sony 耳机）仍展示。
    private static func mergeDevices(
        bluetooth: [BatteryBluetoothProbe.Snapshot],
        hid: [BatteryHIDProbe.Snapshot],
        profiler: [BatterySystemProfilerProbe.Snapshot],
        bleLevels: [String: Int],
        continuity: [BatteryCoreBluetoothMonitor.ContinuitySnapshot],
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
            // Continuity 手机/平板/手表优先保留明确 kind，避免被 .other 覆盖。
            if let existingKind = existing?.kind,
               mergedKind == .other,
               existingKind == .phone || existingKind == .tablet || existingKind == .watch
            {
                mergedKind = existingKind
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
                    charging: charging || (existing?.isCharging ?? false),
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

        // 4) Continuity BLE：近场 iPhone / iPad / Watch（经典蓝牙常显示未连接）。
        for snap in continuity {
            let nameKey = normalizeName(snap.name)
            if let existingID = byName[nameKey] {
                upsert(
                    id: existingID,
                    name: snap.name,
                    kind: snap.kind,
                    percent: snap.percent,
                    charging: snap.isCharging,
                    left: nil,
                    right: nil,
                    casePct: nil
                )
            } else {
                upsert(
                    id: snap.id,
                    name: snap.name,
                    kind: snap.kind,
                    percent: snap.percent,
                    charging: snap.isCharging,
                    left: nil,
                    right: nil,
                    casePct: nil
                )
            }
        }

        // 5) BLE Battery Service 按名回填
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

        // 耳机 / 耳麦：IOBluetooth / system_profiler 常把「仅有 BLE 电量链路」标成已连接
        //（AirPods 在盒内附近尤其如此），但用户侧蓝牙并未真正接上。以 CoreAudio 是否
        // 出现对应蓝牙音频输出为准，避免电量页误报「耳机已连接」。
        let audioNames = connectedBluetoothAudioNames()
        let kept = byAddress.values.filter { device in
            guard isWirelessAudioKind(device.kind) else { return true }
            if device.id.hasPrefix("hid.") { return true }
            let matched = matchesBluetoothAudio(deviceName: device.name, audioNames: audioNames)
            if !matched {
                AppLog.info("Battery", "忽略无音频路由的耳机/耳麦", [
                    "name": device.name,
                    "kind": device.kind.rawValue,
                    "audioOutputs": audioNames.sorted().joined(separator: "|")
                ])
            }
            return matched
        }

        return kept.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isWirelessAudioKind(_ kind: BatteryDeviceKind) -> Bool {
        kind == .headphones || kind == .headset
    }

    /// 当前 HAL 里的蓝牙/蓝牙 LE 输出设备名（已规范化）。
    private static func connectedBluetoothAudioNames() -> Set<String> {
        let ids: [AudioObjectID] = CoreAudioProperty.getArray(
            object: .system,
            kAudioHardwarePropertyDevices
        )
        var names = Set<String>()
        for id in ids {
            let transport: UInt32 = CoreAudioProperty.get(
                object: id,
                kAudioDevicePropertyTransportType
            ) ?? 0
            guard transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
            else { continue }
            // 只要有输出声道就认作可用音频路由（不必是当前默认输出）。
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var dataSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr,
                  dataSize > 0
            else { continue }
            let raw = UnsafeMutableRawPointer.allocate(
                byteCount: Int(dataSize),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, raw) == noErr else {
                continue
            }
            let list = raw.assumingMemoryBound(to: AudioBufferList.self)
            var channels = 0
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                channels += Int(buffer.mNumberChannels)
            }
            guard channels > 0 else { continue }
            if let name = CoreAudioProperty.getCFString(
                object: id,
                kAudioDevicePropertyDeviceNameCFString
            ) {
                let key = normalizeName(name)
                if !key.isEmpty { names.insert(key) }
            }
        }
        return names
    }

    private static func matchesBluetoothAudio(deviceName: String, audioNames: Set<String>) -> Bool {
        let key = normalizeName(deviceName)
        guard !key.isEmpty else { return false }
        if audioNames.contains(key) { return true }
        for audio in audioNames {
            if audio.contains(key) || key.contains(audio) { return true }
        }
        return false
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
        let tipOn = isPeripheralTipEnabled

        for id in lowAlertArmed where !liveIDs.contains(id) {
            lowAlertArmed.remove(id)
        }
        for id in fullAlertArmed where !liveIDs.contains(id) {
            fullAlertArmed.remove(id)
        }

        evaluateConnectAlerts(devices: devices, liveIDs: liveIDs, tipOn: tipOn)

        guard tipOn else {
            AppLog.debug("Battery", "外设提示库卡已关，跳过低电/满电")
            return
        }

        for device in devices {
            guard let percent = device.percent else { continue }

            if percent > threshold + 5 {
                lowAlertArmed.remove(device.id)
                settings.clearSnooze(deviceID: device.id)
            }
            // 未满或未在充电：允许下一轮「充到 100%」再提示；纯满电未插电不提示。
            if percent < 100 || !device.isCharging {
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

            // 满电提示：必须「正在充电」且电量到 100%；已满但未充电（如一直躺在 100%）不弹。
            if settings.fullChargeAlertEnabled,
               device.isCharging,
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
                AppLog.info("Battery", "已投递满电通知", [
                    "name": device.name,
                    "percent": percent,
                    "charging": true
                ])
            } else if settings.fullChargeAlertEnabled,
                      percent >= 100,
                      !device.isCharging
            {
                AppLog.debug("Battery", "满电但未充电，跳过满电通知", [
                    "name": device.name,
                    "percent": percent
                ])
            }
        }
    }

    /// 新接入外设瞬时提示；首轮只记录已知 id，避免启动刷屏。
    private func evaluateConnectAlerts(devices: [BatteryDevice], liveIDs: Set<String>, tipOn: Bool) {
        if !connectSeeded {
            knownDeviceIDs = liveIDs
            connectSeeded = true
            AppLog.debug("Battery", "接入提示已播种已知设备", ["count": liveIDs.count])
            return
        }

        let newcomers = liveIDs.subtracting(knownDeviceIDs)
        knownDeviceIDs = liveIDs

        guard tipOn, settings.connectAlertEnabled, !newcomers.isEmpty else {
            if !newcomers.isEmpty {
                AppLog.debug("Battery", "接入提示已跳过", [
                    "tipOn": tipOn,
                    "connectEnabled": settings.connectAlertEnabled,
                    "newcomers": newcomers.count
                ])
            }
            return
        }

        for id in newcomers {
            guard let device = devices.first(where: { $0.id == id }) else { continue }
            let notice = BatteryPeripheralNotice(
                id: "battery.connect.\(device.id).\(UUID().uuidString.prefix(8))",
                deviceID: device.id,
                deviceName: device.name,
                kind: device.kind,
                percent: device.percent,
                threshold: 0,
                detail: L10n.PeripheralTip.connectNoticeDetail
            )
            IslandNoticeCenter.shared.present(.peripheralConnected(notice))
            AppLog.info("Battery", "已投递接入通知", [
                "name": device.name,
                "percent": device.percent ?? -1
            ])
        }
    }
}
