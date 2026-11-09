import Combine
import Foundation

/// 屏幕取色设置：快捷键、是否写入历史粘贴板。
@MainActor
final class ColorPickSettings: ObservableObject {
    static let shared = ColorPickSettings()

    private enum Key {
        static let chord = "capture.colorPick.hotKey.v1"
        static let saveToHistory = "capture.colorPick.saveToHistory.v1"
        /// 旧语义：曾表示「是否写系统剪贴板」；迁移为 `saveToHistory`。
        static let autoCopyHexLegacy = "capture.colorPick.autoCopyHex.v1"
    }

    private enum Defaults {
        static let saveToHistory = true
    }

    @Published var hotKey: HotKeyChord {
        didSet {
            guard isLoaded else { return }
            persistChord()
        }
    }

    /// 开启：系统剪贴板 + 灵动岛历史；关闭：仅系统剪贴板。
    @Published var saveToHistory: Bool {
        didSet {
            guard isLoaded else { return }
            UserDefaults.standard.set(saveToHistory, forKey: Key.saveToHistory)
            AppLog.info("ColorPick", "写入历史粘贴板已更新", ["on": saveToHistory])
        }
    }

    private var isLoaded = false

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.chord),
           let decoded = try? JSONDecoder().decode(HotKeyChord.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .colorPickDefault
        }
        if defaults.object(forKey: Key.saveToHistory) != nil {
            saveToHistory = defaults.bool(forKey: Key.saveToHistory)
        } else if defaults.object(forKey: Key.autoCopyHexLegacy) != nil {
            saveToHistory = defaults.bool(forKey: Key.autoCopyHexLegacy)
            defaults.set(saveToHistory, forKey: Key.saveToHistory)
        } else {
            saveToHistory = Defaults.saveToHistory
        }
        isLoaded = true
    }

    func restoreDefaults() {
        hotKey = .colorPickDefault
        saveToHistory = Defaults.saveToHistory
        AppLog.warn("ColorPick", "已恢复默认设置", [
            "chord": hotKey.displayString,
            "saveToHistory": saveToHistory
        ])
    }

    private func persistChord() {
        if let data = try? JSONEncoder().encode(hotKey) {
            UserDefaults.standard.set(data, forKey: Key.chord)
        }
    }
}
