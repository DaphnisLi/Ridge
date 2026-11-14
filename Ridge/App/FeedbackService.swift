import AppKit
import Foundation

enum FeedbackKind {
    /// 功能建议。
    case suggestion
    /// Bug / 异常（附带诊断 + 当天日志）。
    case bugReport
    /// 通用反馈。
    case general
}

/// 反馈：优先用系统邮件撰写窗（可附日志文件）；否则回退 mailto。
enum FeedbackService {
    @MainActor
    @discardableResult
    static func openMail(
        kind: FeedbackKind = .general,
        includeDiagnostics: Bool? = nil
    ) -> Bool {
        let attachDiagnostics: Bool
        let attachTodayLog: Bool
        switch kind {
        case .bugReport:
            attachDiagnostics = includeDiagnostics ?? true
            attachTodayLog = true
        case .suggestion, .general:
            attachDiagnostics = includeDiagnostics ?? false
            attachTodayLog = false
        }

        let subject: String
        let prompt: String
        switch kind {
        case .suggestion:
            subject = "Ridge 功能建议 \(AppIdentity.versionLabel)"
            prompt = "请描述你希望的功能或改进："
        case .bugReport:
            subject = "Ridge Bug 反馈 \(AppIdentity.versionLabel)"
            prompt = "请描述现象、复现步骤与期望结果："
        case .general:
            subject = "Ridge 用户反馈 \(AppIdentity.versionLabel)"
            prompt = "请描述问题或建议："
        }

        var body = """
        \(prompt)



        ———
        版本：\(AppIdentity.versionLabel)
        系统：\(ProcessInfo.processInfo.operatingSystemVersionString)
        """
        if attachDiagnostics {
            body += "\n\n" + DiagnosticsExporter.makeReport()
        }

        let todayLog = AppLog.todayLogURL()
        let hasLogFile = FileManager.default.fileExists(atPath: todayLog.path)

        if attachTodayLog, hasLogFile,
           let service = NSSharingService(named: .composeEmail),
           service.canPerform(withItems: [body, todayLog]) {
            service.recipients = [AppIdentity.feedbackEmail]
            service.subject = subject
            service.perform(withItems: [body, todayLog])
            AppLog.warn("Feedback", "已打开邮件撰写并附带当日日志", [
                "kind": "\(kind)",
                "log": todayLog.lastPathComponent
            ])
            return true
        }

        if attachTodayLog {
            if let logText = AppLog.readTodayLog(maxBytes: 80_000) {
                body += "\n\n——— 当日日志（\(todayLog.lastPathComponent)）———\n\(logText)\n"
            } else {
                body += "\n\n（当日尚无落盘日志：\(todayLog.path)）\n"
            }
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppIdentity.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else {
            AppLog.error("Feedback", "无法构造 mailto", ["kind": "\(kind)"])
            return false
        }
        let ok = NSWorkspace.shared.open(url)
        AppLog.warn("Feedback", "打开反馈邮件", [
            "ok": ok,
            "kind": "\(kind)",
            "diagnostics": attachDiagnostics,
            "todayLog": attachTodayLog,
            "via": "mailto"
        ])
        return ok
    }
}
