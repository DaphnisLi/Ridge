import AppKit
import Foundation

/// 反馈：mailto 模板，可选附带诊断摘要。
enum FeedbackService {
    @MainActor
    @discardableResult
    static func openMail(includeDiagnostics: Bool) -> Bool {
        let subject = "Ridge 反馈 \(AppIdentity.versionLabel)"
        var body = """
        请描述问题或建议：



        ———
        版本：\(AppIdentity.versionLabel)
        系统：\(ProcessInfo.processInfo.operatingSystemVersionString)
        """
        if includeDiagnostics {
            body += "\n\n" + DiagnosticsExporter.makeReport()
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppIdentity.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else {
            AppLog.error("Feedback", "无法构造 mailto")
            return false
        }
        let ok = NSWorkspace.shared.open(url)
        AppLog.warn("Feedback", "打开反馈邮件", ["ok": ok, "diagnostics": includeDiagnostics])
        return ok
    }
}
