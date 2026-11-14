import AppKit
import CoreGraphics
import Foundation

/// 一键诊断摘要（用户确认后复制到剪贴板）。
enum DiagnosticsExporter {
    @MainActor
    static func makeReport() -> String {
        MeetingCalendarService.shared.refreshAuthStatus()
        let cal = "\(MeetingCalendarService.shared.authStatus)"
        let screen = CGPreflightScreenCaptureAccess()
        let input = ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
        let login = LoginItemService.shared.isEnabled
        let lines: [String] = [
            "Ridge Diagnostics",
            "version: \(AppIdentity.versionLabel)",
            "path: \(AppIdentity.bundlePath)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "loginItem: \(login)",
            "calendar: \(cal)",
            "screenCapture: \(screen)",
            "inputMonitoring: \(input)",
            "logDir: \(AppLog.logsDirectory.path)",
            "todayLog: \(AppLog.todayLogURL().path)",
            "appSupport: \(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Ridge").path ?? "?")"
        ]
        return lines.joined(separator: "\n")
    }

    @MainActor
    @discardableResult
    static func copyToPasteboard() -> Bool {
        let report = makeReport()
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(report, forType: .string)
        AppLog.warn("Diagnostics", "已复制诊断信息", ["chars": report.count, "ok": ok])
        return ok
    }
}
