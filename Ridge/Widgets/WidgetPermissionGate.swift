import AppKit
import CoreBluetooth
import CoreGraphics
import Foundation

/// 小组件 / 控制台磁贴开关打开时：按能力校验并申请系统权限（每次开启都走一遍）。
/// 无对应权限需求的 id 直接跳过；已授权则只记日志不重复打扰。
enum WidgetPermissionGate {
    enum Need: String, CaseIterable {
        case calendar
        case screenCapture
        case bluetooth
        case inputMonitoring
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
        switch need {
        case .calendar:
            await ensureCalendar(reason: reason)
        case .screenCapture:
            ensureScreenCapture(reason: reason)
        case .bluetooth:
            ensureBluetooth(reason: reason)
        case .inputMonitoring:
            ensureInputMonitoringAccess(reason: reason)
        }
    }

    @MainActor
    private static func ensureCalendar(reason: String) async {
        let calendar = MeetingCalendarService.shared
        calendar.refreshAuthStatus()
        if calendar.authStatus == .authorized {
            AppLog.debug("PrivacyHub", "日历已授权，跳过申请", ["reason": reason])
            return
        }
        AppLog.info("PrivacyHub", "申请日历权限", ["reason": reason, "status": "\(calendar.authStatus)"])
        let granted = await calendar.requestAccess()
        AppLog.info("PrivacyHub", "日历权限结果", ["reason": reason, "granted": granted])
    }

    @MainActor
    private static func ensureScreenCapture(reason: String) {
        if CGPreflightScreenCaptureAccess() {
            AppLog.debug("PrivacyHub", "屏幕录制已授权，刷新 Tap 状态", ["reason": reason])
            SoundSession.shared.requestScreenCaptureAccess()
            return
        }
        AppLog.info("PrivacyHub", "申请屏幕录制权限", ["reason": reason])
        NSApp.activate(ignoringOtherApps: true)
        SoundSession.shared.requestScreenCaptureAccess()
        let granted = CGPreflightScreenCaptureAccess()
        AppLog.info("PrivacyHub", "屏幕录制权限结果", ["reason": reason, "granted": granted])
        if !granted {
            SystemPrivacyOpener.open(anchor: "Privacy_ScreenCapture")
        }
    }

    @MainActor
    private static func ensureBluetooth(reason: String) {
        switch CBManager.authorization {
        case .allowedAlways:
            AppLog.debug("PrivacyHub", "蓝牙已授权，跳过申请", ["reason": reason])
            BatterySession.shared.start()
            return
        case .denied, .restricted:
            AppLog.warn("PrivacyHub", "蓝牙已拒绝，打开系统设置", [
                "reason": reason,
                "auth": bluetoothAuthLabel()
            ])
            SystemPrivacyOpener.open(anchor: "Privacy_Bluetooth")
            return
        default:
            AppLog.info("PrivacyHub", "申请蓝牙权限（拉起电量监视）", [
                "reason": reason,
                "auth": bluetoothAuthLabel()
            ])
            // 创建 CBCentralManager 会触发系统授权；已开模块也会复用此路径。
            BatterySession.shared.start()
        }
    }

    @MainActor
    private static func ensureInputMonitoringAccess(reason: String) {
        if ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess {
            AppLog.debug("PrivacyHub", "输入监控已授权，拉起击键监听", ["reason": reason])
            ResourceKeystrokeMonitor.shared.start()
            ResourceMonitorSession.shared.refreshInputMonitoringStatus()
            return
        }
        AppLog.info("PrivacyHub", "申请输入监控权限", ["reason": reason])
        let granted = ResourceKeystrokeMonitor.shared.requestInputMonitoringAccess()
        ResourceMonitorSession.shared.refreshInputMonitoringStatus()
        AppLog.info("PrivacyHub", "输入监控权限结果", ["reason": reason, "granted": granted])
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
