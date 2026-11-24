import Foundation

/// 下载完成常驻：点击动作 / 快捷键等（库开关走 `WidgetSettings`）。
@MainActor
final class DownloadCompleteSettings: ObservableObject {
    static let shared = DownloadCompleteSettings()

    private enum Key {
        /// v3：与稿面一致，默认「用默认 App 打开」。
        static let clickAction = "downloadComplete.clickAction.v3"
        static let keyboardShortcutEnabled = "downloadComplete.keyboardShortcutEnabled.v1"
        static let hotKey = "downloadComplete.hotKey.v1"
    }

    @Published var clickAction: DownloadCompleteClickAction {
        didSet {
            guard clickAction != oldValue else { return }
            UserDefaults.standard.set(clickAction.rawValue, forKey: Key.clickAction)
            AppLog.info("Download", "点击动作已改", ["action": clickAction.rawValue])
        }
    }

    /// 完成态驻留期间击键直达（与点按同一动作）。
    @Published var keyboardShortcutEnabled: Bool {
        didSet {
            guard keyboardShortcutEnabled != oldValue else { return }
            UserDefaults.standard.set(keyboardShortcutEnabled, forKey: Key.keyboardShortcutEnabled)
            AppLog.info("Download", "快捷键直达已改", ["on": keyboardShortcutEnabled])
            DownloadCompleteSession.shared.refreshOpenShortcutMonitor()
        }
    }

    /// 用户可录制的打开快捷键（默认 ⌘O）。
    @Published var hotKey: HotKeyChord {
        didSet {
            guard isLoaded else { return }
            guard hotKey != oldValue else { return }
            persistHotKey()
            AppLog.info("Download", "快捷键组合已改", ["chord": hotKey.displayString])
            DownloadCompleteSession.shared.refreshOpenShortcutMonitor()
        }
    }

    private var isLoaded = false

    private init() {
        let raw = UserDefaults.standard.string(forKey: Key.clickAction)
            ?? DownloadCompleteClickAction.openWithDefaultApp.rawValue
        clickAction = DownloadCompleteClickAction(rawValue: raw) ?? .openWithDefaultApp
        if UserDefaults.standard.object(forKey: Key.keyboardShortcutEnabled) == nil {
            keyboardShortcutEnabled = true
        } else {
            keyboardShortcutEnabled = UserDefaults.standard.bool(forKey: Key.keyboardShortcutEnabled)
        }
        if let data = UserDefaults.standard.data(forKey: Key.hotKey),
           let decoded = try? JSONDecoder().decode(HotKeyChord.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .downloadCompleteDefault
        }
        isLoaded = true
    }

    func restoreDefaults() {
        clickAction = .openWithDefaultApp
        keyboardShortcutEnabled = true
        hotKey = .downloadCompleteDefault
        AppLog.info("Download", "已恢复下载完成默认设置", [
            "chord": hotKey.displayString
        ])
    }

    private func persistHotKey() {
        if let data = try? JSONEncoder().encode(hotKey) {
            UserDefaults.standard.set(data, forKey: Key.hotKey)
        }
    }
}
