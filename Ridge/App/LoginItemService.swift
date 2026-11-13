import AppKit
import Combine
import Foundation
import ServiceManagement

/// 开机自启（`SMAppService.mainApp`）。失败时引导用户打开系统「登录项」。
@MainActor
final class LoginItemService: ObservableObject {
    static let shared = LoginItemService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    private init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        AppLog.debug("LoginItem", "登录项状态", ["status": "\(status.rawValue)", "enabled": isEnabled])
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
            refresh()
            AppLog.warn("LoginItem", "开机自启已更新", ["enabled": isEnabled, "requested": enabled])
            return isEnabled == enabled
        } catch {
            lastError = error.localizedDescription
            AppLog.error("LoginItem", "开机自启切换失败", [
                "requested": enabled,
                "error": error.localizedDescription
            ])
            refresh()
            return false
        }
    }

    /// 打开系统设置 → 通用 → 登录项。
    func openSystemLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.LoginItemsPref",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.users?LoginItems"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                AppLog.info("LoginItem", "已打开系统登录项设置", ["url": raw])
                return
            }
        }
        AppLog.warn("LoginItem", "无法打开系统登录项设置")
    }
}
