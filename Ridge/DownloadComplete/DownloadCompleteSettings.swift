import Foundation

/// 下载完成常驻：点击动作等（库开关走 `WidgetSettings`）。
@MainActor
final class DownloadCompleteSettings: ObservableObject {
    static let shared = DownloadCompleteSettings()

    private enum Key {
        static let clickAction = "downloadComplete.clickAction.v1"
    }

    @Published var clickAction: DownloadCompleteClickAction {
        didSet {
            guard clickAction != oldValue else { return }
            UserDefaults.standard.set(clickAction.rawValue, forKey: Key.clickAction)
            AppLog.info("Download", "点击动作已改", ["action": clickAction.rawValue])
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Key.clickAction)
            ?? DownloadCompleteClickAction.openWithDefaultApp.rawValue
        clickAction = DownloadCompleteClickAction(rawValue: raw) ?? .openWithDefaultApp
    }

    func restoreDefaults() {
        clickAction = .openWithDefaultApp
        AppLog.info("Download", "已恢复下载完成默认设置")
    }
}
