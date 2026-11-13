import AppKit
import Foundation

enum LegalDocumentKind {
    case privacy
    case terms

    var resourceName: String {
        switch self {
        case .privacy: return "privacy.zh-Hans"
        case .terms: return "terms.zh-Hans"
        }
    }

    var remoteURL: URL {
        switch self {
        case .privacy: return AppIdentity.privacyPolicyURL
        case .terms: return AppIdentity.termsOfUseURL
        }
    }
}

/// 优先打开包内法律文稿；失败再尝试官网 URL。
enum LegalDocumentOpener {
    @MainActor
    @discardableResult
    static func open(_ kind: LegalDocumentKind) -> Bool {
        if let bundled = bundledURL(kind), NSWorkspace.shared.open(bundled) {
            AppLog.warn("Legal", "已打开本地法律文稿", ["kind": kind.resourceName])
            return true
        }
        if NSWorkspace.shared.open(kind.remoteURL) {
            AppLog.warn("Legal", "已打开在线法律文稿", ["kind": kind.resourceName, "url": kind.remoteURL.absoluteString])
            return true
        }
        AppLog.error("Legal", "无法打开法律文稿", ["kind": kind.resourceName])
        return false
    }

    static func bundledURL(_ kind: LegalDocumentKind) -> URL? {
        let name = kind.resourceName
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Legal") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "md") {
            return url
        }
        // 开发态：仓库 docs / Resources 相对路径兜底。
        let candidates = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Legal/\(name).md"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Legal/\(name).md")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
