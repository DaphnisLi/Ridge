import Foundation

/// 前台驻留展示名与分类：系统进程用可读中文，避免 `loginwindow` 这类内核名直接上屏。
enum ResourceFocusPresentation {
    static func displayName(bundleID: String, fallback: String) -> String {
        let bid = bundleID.lowercased()
        let raw = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let hay = raw.lowercased()

        if bid == "com.apple.loginwindow" || hay == "loginwindow" {
            return L10n.ResourceMonitor.focusNameLoginWindow
        }
        if bid == "com.apple.screensaver.engine"
            || bid.hasPrefix("com.apple.screensaver")
            || hay.contains("screensaver")
        {
            return L10n.ResourceMonitor.focusNameScreenSaver
        }
        if bid == "com.apple.dock" || hay == "dock" {
            return L10n.ResourceMonitor.focusNameDock
        }
        if bid == "com.apple.systemuiserver" || hay == "systemuiserver" {
            return L10n.ResourceMonitor.focusNameSystemUI
        }
        if bid.hasPrefix("com.apple.") && (hay.isEmpty || hay == bid) {
            // 兜底：无本地化名的 Apple 系统进程
            return L10n.ResourceMonitor.focusNameSystemProcess
        }
        return raw.isEmpty ? bundleID : raw
    }

    static func category(bundleID: String, name: String) -> ResourceFocusCategory {
        if isSystemIdle(bundleID: bundleID, name: name) {
            return .systemIdle
        }
        let hay = (bundleID + " " + name).lowercased()
        if hay.contains("chrome") || hay.contains("safari") || hay.contains("firefox")
            || hay.contains("arc") || hay.contains("edge") || hay.contains("browser")
            || hay.contains("qqbrowser") || hay.contains("brave")
        {
            return .browser
        }
        if hay.contains("code") || hay.contains("xcode") || hay.contains("cursor")
            || hay.contains("jetbrains") || hay.contains("webstorm") || hay.contains("idea")
            || hay.contains("sublime") || hay.contains("vim") || hay.contains("neovim")
        {
            return .ide
        }
        if hay.contains("terminal") || hay.contains("iterm") || hay.contains("warp")
            || hay.contains("alacritty") || hay.contains("kitty") || hay.contains("shell")
        {
            return .terminal
        }
        return .other
    }

    /// 锁屏 / 屏保等：用户未在真正操作 App。
    static func isSystemIdle(bundleID: String, name: String) -> Bool {
        let bid = bundleID.lowercased()
        let hay = name.lowercased()
        if bid == "com.apple.loginwindow" || hay == "loginwindow" { return true }
        if bid == "com.apple.screensaver.engine" || bid.hasPrefix("com.apple.screensaver") {
            return true
        }
        if hay.contains("screensaver") { return true }
        return false
    }
}
