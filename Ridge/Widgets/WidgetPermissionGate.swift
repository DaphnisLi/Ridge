import AppKit
import CoreBluetooth
import CoreGraphics
import Foundation

/// 小组件 / 控制台磁贴开关打开时：按能力校验并申请系统权限（每次开启都走一遍）。
/// 无对应权限需求的 id 直接跳过；已授权则只记日志不重复打扰。
/// 首次引导批量开功能时，按所选小组件汇总权限队列逐项申请。
enum WidgetPermissionGate {
    enum Need: String, CaseIterable, Codable {
        case calendar
        case screenCapture
        case bluetooth
        case inputMonitoring
        /// Wi‑Fi SSID（网络 tip）。
        case location
        /// 系统 Focus 模式名 / 图标 / 结束时间。
        case fullDiskAccess
    }

    /// 单次申请结果：引导第 3 步据此决定是否进入「等待重开」。
    enum EnsureOutcome: Equatable {
        case satisfied
        case stillNeeded
        /// 已打开系统设置；用户勾选后可能需重开 App。
        case awaitingSystemSettingsRelaunch
    }

    @MainActor
    static func isSatisfied(_ need: Need) -> Bool {
        switch need {
        case .calendar:
            MeetingCalendarService.shared.refreshAuthStatus()
            return MeetingCalendarService.shared.authStatus == .authorized
        case .screenCapture:
            return CGPreflightScreenCaptureAccess()
        case .bluetooth:
            return CBManager.authorization == .allowedAlways
        case .inputMonitoring:
            return ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
        case .location:
            return NetworkLinkLocationAccess.shared.isAuthorized
        case .fullDiskAccess:
            return SystemFocusStoreReader.canReadStore()
        }
    }

    /// 授权后重开瞬间 TCC 探针可能滞后；同步刷一遍再读 isSatisfied。
    @MainActor
    static func refreshSatisfactionProbes(reason: String) {
        MeetingCalendarService.shared.refreshAuthStatus()
        NetworkLinkLocationAccess.shared.reloadStatusFromSystem(reason: reason)
        ResourceMonitorSession.shared.refreshInputMonitoringStatus()
        SystemFocusSession.shared.recheckAccess(reason: "probe:\(reason)")
        AppLog.info("PrivacyHub", "已刷新权限探针", [
            "reason": reason,
            "calendar": MeetingCalendarService.shared.authStatus == .authorized,
            "screen": CGPreflightScreenCaptureAccess(),
            "bluetooth": CBManager.authorization == .allowedAlways,
            "input": ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess,
            "location": NetworkLinkLocationAccess.shared.isAuthorized,
            "fullDisk": SystemFocusStoreReader.canReadStore()
        ])
    }

    @MainActor
    static func title(for need: Need) -> String {
        switch need {
        case .calendar: return L10n.PrivacyHub.calendarTitle
        case .screenCapture: return L10n.PrivacyHub.screenCaptureTitle
        case .bluetooth: return L10n.PrivacyHub.bluetoothTitle
        case .inputMonitoring: return L10n.PrivacyHub.inputMonitoringTitle
        case .location: return L10n.PrivacyHub.locationTitle
        case .fullDiskAccess: return L10n.PrivacyHub.fullDiskTitle
        }
    }

    @MainActor
    static func subtitle(for need: Need) -> String {
        switch need {
        case .calendar: return L10n.PrivacyHub.calendarSubtitle
        case .screenCapture: return L10n.PrivacyHub.screenCaptureSubtitle
        case .bluetooth: return L10n.PrivacyHub.bluetoothSubtitle
        case .inputMonitoring: return L10n.PrivacyHub.inputMonitoringSubtitle
        case .location: return L10n.PrivacyHub.locationSubtitle
        case .fullDiskAccess: return L10n.PrivacyHub.fullDiskSubtitle
        }
    }

    /// 库内小组件 id（含 `system.controlDeck.*` 页 id）。
    static func needs(forWidgetID id: WidgetID) -> [Need] {
        let prefix = ControlDeckSettings.pageIDPrefix + "."
        if id.hasPrefix(prefix) {
            let module = String(id.dropFirst(prefix.count))
            return needs(forDeckModule: module)
        }
        switch id {
        case "builtin.meeting":
            return [.calendar]
        case "builtin.colorPick", "builtin.ocrSelect":
            return [.screenCapture]
        case "builtin.peripheralTip":
            return [.bluetooth]
        case "builtin.networkLinkTip":
            return [.location]
        case "builtin.systemFocusTip":
            return [.fullDiskAccess]
        default:
            return []
        }
    }

    /// 控制台模块短 id：`battery` / `volume` / …
    static func needs(forDeckModule id: String) -> [Need] {
        switch id {
        case "volume":
            return [.screenCapture]
        case "battery":
            return [.bluetooth]
        default:
            return []
        }
    }

    @MainActor
    static func ensureOnEnable(widgetID: WidgetID) async {
        let list = needs(forWidgetID: widgetID)
        guard !list.isEmpty else { return }
        AppLog.info("PrivacyHub", "开启小组件，校验权限", [
            "id": widgetID,
            "needs": list.map(\.rawValue).joined(separator: ",")
        ])
        for need in list {
            await ensure(need, reason: "widgetEnable:\(widgetID)")
        }
    }

    @MainActor
    static func ensureOnEnable(deckModule id: String) async {
        let list = needs(forDeckModule: id)
        guard !list.isEmpty else { return }
        AppLog.info("PrivacyHub", "开启控制台磁贴，校验权限", [
            "id": id,
            "needs": list.map(\.rawValue).joined(separator: ",")
        ])
        for need in list {
            await ensure(need, reason: "deckEnable:\(id)")
        }
    }

    /// 「专注与击键」设置页进入时申请输入监控（不在 App 启动时申请）。
    @MainActor
    static func ensureInputMonitoring(reason: String) {
        ensureInputMonitoringAccess(reason: reason)
    }

    @MainActor
    private static func ensure(_ need: Need, reason: String) async {
        _ = await ensureOne(need, reason: reason)
    }

    /// 引导逐项申请；返回是否已满足 / 仍缺 / 需去系统设置后重开。
    @MainActor
    @discardableResult
    static func ensureOne(_ need: Need, reason: String) async -> EnsureOutcome {
        if isSatisfied(need) {
            // 已授权时仍做一次轻量接通（如击键 tap / 混音 Tap）。
            switch need {
            case .screenCapture:
                SoundSession.shared.requestScreenCaptureAccess()
            case .bluetooth:
                BatterySession.shared.start()
            case .inputMonitoring:
                ResourceKeystrokeMonitor.shared.start()
                ResourceMonitorSession.shared.refreshInputMonitoringStatus()
            case .calendar:
                MeetingCalendarService.shared.start()
            case .location:
                NetworkLinkSession.shared.refresh(reason: "locationAlreadyAuthorized:\(reason)")
            case .fullDiskAccess:
                SystemFocusSession.shared.recheckAccess(reason: "fullDiskAlreadyAuthorized:\(reason)")
            }
            return .satisfied
        }
        switch need {
        case .calendar:
            return await ensureCalendar(reason: reason)
        case .screenCapture:
            return ensureScreenCapture(reason: reason)
        case .bluetooth:
            return await ensureBluetooth(reason: reason)
        case .inputMonitoring:
            return ensureInputMonitoringAccess(reason: reason)
        case .location:
            return await ensureLocation(reason: reason)
        case .fullDiskAccess:
            return ensureFullDiskAccess(reason: reason)
        }
    }

    @MainActor
    private static func ensureCalendar(reason: String) async -> EnsureOutcome {
        let calendar = MeetingCalendarService.shared
        calendar.refreshAuthStatus()
        AppLog.info("PrivacyHub", "申请日历权限", ["reason": reason, "status": "\(calendar.authStatus)"])
        let granted = await calendar.requestAccess()
        AppLog.info("PrivacyHub", "日历权限结果", ["reason": reason, "granted": granted])
        return granted || isSatisfied(.calendar) ? .satisfied : .stillNeeded
    }

    /// 本进程是否已弹过系统「录屏」预授权窗。须先 CGRequest 才会把 App 登记进列表；
    /// 但 CGRequest 与自开设置页叠在一起会双开，故首次只 request，再次才 open。
    @MainActor
    private static var didPromptScreenCaptureThisSession = false

    @MainActor
    private static func ensureScreenCapture(reason: String) -> EnsureOutcome {
        if isSatisfied(.screenCapture) {
            SoundSession.shared.requestScreenCaptureAccess()
            AppLog.info("PrivacyHub", "屏幕录制已授权", ["reason": reason])
            return .satisfied
        }
        NSApp.activate(ignoringOtherApps: true)
        if !didPromptScreenCaptureThisSession {
            didPromptScreenCaptureThisSession = true
            // 必须 CGRequest：否则隐私列表里没有 Ridge。不要同时 SystemPrivacyOpener——
            // 新系统上 request 往往立刻返回，设置页会抢在用户点小窗「打开系统设置」之前出现。
            AppLog.warn("PrivacyHub", "申请屏幕录制：系统对话框登记 App", ["reason": reason])
            let granted = CGRequestScreenCaptureAccess()
            if granted || isSatisfied(.screenCapture) {
                AppLog.info("PrivacyHub", "屏幕录制权限结果", ["reason": reason, "granted": true])
                return .satisfied
            }
            AppLog.warn("PrivacyHub", "屏幕录制待用户在系统对话框中打开设置", ["reason": reason])
            return .awaitingSystemSettingsRelaunch
        }
        AppLog.warn("PrivacyHub", "屏幕录制仍缺，打开系统设置", ["reason": reason])
        SystemPrivacyOpener.open(anchor: "Privacy_ScreenCapture")
        return .awaitingSystemSettingsRelaunch
    }

    @MainActor
    private static func ensureBluetooth(reason: String) async -> EnsureOutcome {
        switch CBManager.authorization {
        case .denied, .restricted:
            AppLog.warn("PrivacyHub", "蓝牙已拒绝，打开系统设置", [
                "reason": reason,
                "auth": bluetoothAuthLabel()
            ])
            SystemPrivacyOpener.open(anchor: "Privacy_Bluetooth")
            return .awaitingSystemSettingsRelaunch
        case .allowedAlways:
            BatterySession.shared.start()
            return .satisfied
        default:
            AppLog.warn("PrivacyHub", "申请蓝牙权限（拉起电量监视并等待结果）", [
                "reason": reason,
                "auth": bluetoothAuthLabel(),
                "note": "HID 电量探测在蓝牙未决时跳过，避免叠弹输入监控"
            ])
            // start → CoreBluetooth 弹蓝牙框；HID 在 notDetermined 时由 BatteryHIDProbe 跳过。
            BatterySession.shared.start()
            if isSatisfied(.bluetooth) {
                return .satisfied
            }
            // 系统蓝牙对话框是异步的：等用户点完再返回，避免引导以为「点过授权」就跳步。
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                switch CBManager.authorization {
                case .allowedAlways:
                    AppLog.warn("PrivacyHub", "蓝牙权限已授予", ["reason": reason])
                    return .satisfied
                case .denied, .restricted:
                    AppLog.warn("PrivacyHub", "蓝牙已拒绝，打开系统设置", [
                        "reason": reason,
                        "auth": bluetoothAuthLabel()
                    ])
                    SystemPrivacyOpener.open(anchor: "Privacy_Bluetooth")
                    return .awaitingSystemSettingsRelaunch
                default:
                    continue
                }
            }
            AppLog.warn("PrivacyHub", "蓝牙权限仍待用户确认", [
                "reason": reason,
                "auth": bluetoothAuthLabel()
            ])
            return .stillNeeded
        }
    }

    @MainActor
    private static func ensureInputMonitoringAccess(reason: String) -> EnsureOutcome {
        AppLog.info("PrivacyHub", "申请输入监控权限", ["reason": reason])
        let granted = ResourceKeystrokeMonitor.shared.requestInputMonitoringAccess()
        ResourceMonitorSession.shared.refreshInputMonitoringStatus()
        AppLog.info("PrivacyHub", "输入监控权限结果", ["reason": reason, "granted": granted])
        if granted || isSatisfied(.inputMonitoring) {
            return .satisfied
        }
        return .awaitingSystemSettingsRelaunch
    }

    @MainActor
    private static func ensureLocation(reason: String) async -> EnsureOutcome {
        let access = NetworkLinkLocationAccess.shared
        AppLog.warn("PrivacyHub", "申请定位权限（Wi‑Fi 名称）", [
            "reason": reason,
            "status": NetworkLinkLocationAccess.describe(access.status)
        ])
        if access.isAuthorized {
            NetworkLinkSession.shared.refresh(reason: "locationGateSatisfied:\(reason)")
            return .satisfied
        }
        if access.isDeniedOrRestricted {
            access.openSystemPrivacySettings()
            return .awaitingSystemSettingsRelaunch
        }
        let granted = await access.requestAccessAwaitingResult(reason: reason)
        if granted || isSatisfied(.location) {
            AppLog.warn("PrivacyHub", "定位权限已授予", ["reason": reason])
            return .satisfied
        }
        if access.isDeniedOrRestricted {
            access.openSystemPrivacySettings()
            return .awaitingSystemSettingsRelaunch
        }
        AppLog.warn("PrivacyHub", "定位权限仍待用户确认", [
            "reason": reason,
            "status": NetworkLinkLocationAccess.describe(access.status)
        ])
        return .stillNeeded
    }

    @MainActor
    private static func ensureFullDiskAccess(reason: String) -> EnsureOutcome {
        if SystemFocusStoreReader.canReadStore() {
            SystemFocusSession.shared.recheckAccess(reason: "fullDiskGateSatisfied:\(reason)")
            return .satisfied
        }
        AppLog.warn("PrivacyHub", "打开完全磁盘访问（系统 Focus tip）", ["reason": reason])
        SystemPrivacyOpener.open(anchor: "Privacy_AllFiles")
        // 授权后 TCC 对已运行进程常需重开；与录屏同口径。
        return .awaitingSystemSettingsRelaunch
    }

    private static func bluetoothAuthLabel() -> String {
        switch CBManager.authorization {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .allowedAlways: return "allowedAlways"
        @unknown default: return "unknown"
        }
    }
}
