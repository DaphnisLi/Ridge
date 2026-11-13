import AppKit
import Combine
import Foundation

/// 官网版检查更新入口。
/// Sparkle 二进制包与 XcodeGen embed 尚不稳；当前打开发版页，并在 `SUPublicEDKey` / appcast 就绪后接回 Sparkle。
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var automaticallyChecks: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecks, forKey: AppIdentity.autoCheckUpdatesKey)
            AppLog.warn("Update", "自动检查更新已更新", ["enabled": automaticallyChecks])
        }
    }

    @Published private(set) var lastMessage: String?

    private init() {
        let stored = UserDefaults.standard.object(forKey: AppIdentity.autoCheckUpdatesKey) as? Bool
        automaticallyChecks = stored ?? true
    }

    func start() {
        AppLog.warn("Update", "更新服务已启动", [
            "auto": automaticallyChecks,
            "feed": AppIdentity.appcastURL.absoluteString,
            "mode": "releasesPage"
        ])
        // 自动检查：无 Sparkle 时不弹窗骚扰，仅记录；用户点「检查更新」再打开页面。
    }

    func checkForUpdates(userInitiated: Bool) {
        AppLog.warn("Update", "检查更新（发版页）", ["user": userInitiated])
        lastMessage = L10n.About.updateFallbackHint
        let ok = NSWorkspace.shared.open(AppIdentity.releasesURL)
        if !ok {
            lastMessage = L10n.About.actionFailed
            AppLog.error("Update", "无法打开发版页")
        }
    }
}
