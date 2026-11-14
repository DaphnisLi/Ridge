import AppKit
import Foundation

/// 打开系统「隐私与安全性」对应面板。
enum SystemPrivacyOpener {
    @MainActor
    @discardableResult
    static func open(anchor: String) -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                AppLog.info("PrivacyHub", "已打开系统隐私设置", ["url": raw])
                return true
            }
        }
        AppLog.warn("PrivacyHub", "无法打开系统隐私设置", ["anchor": anchor])
        return false
    }
}
