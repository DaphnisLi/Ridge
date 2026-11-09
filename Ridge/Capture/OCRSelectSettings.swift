import Combine
import Foundation

/// 框选文字提取设置：快捷键、是否写入历史粘贴板。
@MainActor
final class OCRSelectSettings: ObservableObject {
    static let shared = OCRSelectSettings()

    private enum Key {
        static let chord = "capture.ocrSelect.hotKey.v1"
        static let saveToHistory = "capture.ocrSelect.saveToHistory.v1"
        /// 旧语义：曾表示「是否写系统剪贴板」；迁移为 `saveToHistory`。
        static let autoWriteClipboardLegacy = "capture.ocrSelect.autoWriteClipboard.v1"
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
            AppLog.info("OCRSelect", "写入历史粘贴板已更新", ["on": saveToHistory])
        }
    }

    private var isLoaded = false

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.chord),
           let decoded = try? JSONDecoder().decode(HotKeyChord.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .ocrSelectDefault
        }
        if defaults.object(forKey: Key.saveToHistory) != nil {
            saveToHistory = defaults.bool(forKey: Key.saveToHistory)
        } else if defaults.object(forKey: Key.autoWriteClipboardLegacy) != nil {
            saveToHistory = defaults.bool(forKey: Key.autoWriteClipboardLegacy)
            defaults.set(saveToHistory, forKey: Key.saveToHistory)
        } else {
            saveToHistory = Defaults.saveToHistory
        }
        isLoaded = true
    }

    func restoreDefaults() {
        hotKey = .ocrSelectDefault
        saveToHistory = Defaults.saveToHistory
        AppLog.warn("OCRSelect", "已恢复默认设置", [
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
