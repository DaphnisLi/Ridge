import AppKit
import CoreBluetooth
import CoreGraphics
import Foundation

/// 小组件 / 控制台磁贴开关打开时：按能力校验并申请系统权限（每次开启都走一遍）。
/// 无对应权限需求的 id 直接跳过；已授权则只记日志不重复打扰。
enum WidgetPermissionGate {
    enum Need: String, CaseIterable, Codable {
        case calendar
        case screenCapture
        case bluetooth
        case inputMonitoring
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
        }
    }

    @MainActor
    static func title(for need: Need) -> String {
        switch need {
        case .calendar: return L10n.PrivacyHub.calendarTitle
        case .screenCapture: return L10n.PrivacyHub.screenCaptureTitle
        case .bluetooth: return L10n.PrivacyHub.bluetoothTitle
        case .inputMonitoring: return L10n.PrivacyHub.inputMonitoringTitle
        }
    }

    @MainActor
    static func subtitle(for need: Need) -> String {
        switch need {
        case .calendar: return L10n.PrivacyHub.calendarSubtitle
        case .screenCapture: return L10n.PrivacyHub.screenCaptureSubtitle
        case .bluetooth: return L10n.PrivacyHub.bluetoothSubtitle
        case .inputMonitoring: return L10n.PrivacyHub.inputMonitoringSubtitle
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
            }
            return .satisfied
        }
        switch need {
        case .calendar:
            return await ensureCalendar(reason: reason)
        case .screenCapture:
            return ensureScreenCapture(reason: reason)
        case .bluetooth:
            return ensureBluetooth(reason: reason)
        case .inputMonitoring:
            return ensureInputMonitoringAccess(reason: reason)
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

    @MainActor
    private static func ensureScreenCapture(reason: String) -> EnsureOutcome {
        AppLog.info("PrivacyHub", "申请屏幕录制权限", ["reason": reason])
        NSApp.activate(ignoringOtherApps: true)
        SoundSession.shared.requestScreenCaptureAccess()
        if isSatisfied(.screenCapture) {
            AppLog.info("PrivacyHub", "屏幕录制权限结果", ["reason": reason, "granted": true])
            return .satisfied
        }
        SystemPrivacyOpener.open(anchor: "Privacy_ScreenCapture")
        AppLog.info("PrivacyHub", "屏幕录制未当场授权，已打开系统设置", ["reason": reason])
        return .awaitingSystemSettingsRelaunch
    }

    @MainActor
    private static func ensureBluetooth(reason: String) -> EnsureOutcome {
        switch CBManager.authorization {
        case .denied, .restricted:
            AppLog.warn("PrivacyHub", "蓝牙已拒绝，打开系统设置", [
                "reason": reason,
                "auth": bluetoothAuthLabel()
            ])
            SystemPrivacyOpener.open(anchor: "Privacy_Bluetooth")
            return .awaitingSystemSettingsRelaunch
        default:
            AppLog.info("PrivacyHub", "申请蓝牙权限（拉起电量监视）", [
                "reason": reason,
                "auth": bluetoothAuthLabel()
            ])
            BatterySession.shared.start()
            if isSatisfied(.bluetooth) {
                return .satisfied
            }
            // 系统弹窗可能稍后才出结果；未立刻授权则视为仍缺，用户可再点。
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
