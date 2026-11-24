import Foundation

/// Ridge 内可录制快捷键的归属；录制时互斥检查，避免两功能抢同一组合。
enum HotKeyOwnerID: String, CaseIterable, Equatable {
    case colorPick = "builtin.colorPick"
    case ocrSelect = "builtin.ocrSelect"
    case downloadComplete = "builtin.downloadComplete"

    var displayName: String {
        switch self {
        case .colorPick: return L10n.ColorPick.widgetName
        case .ocrSelect: return L10n.OCRSelect.widgetName
        case .downloadComplete: return L10n.DownloadComplete.widgetName
        }
    }

    /// 当前落盘和弦（不论功能开关）。
    @MainActor
    var currentChord: HotKeyChord {
        switch self {
        case .colorPick:
            return ColorPickSettings.shared.hotKey
        case .ocrSelect:
            return OCRSelectSettings.shared.hotKey
        case .downloadComplete:
            return DownloadCompleteSettings.shared.hotKey
        }
    }

    /// 若 `chord` 已被其它归属占用，返回对方；`excluding` 为正在编辑的一方。
    @MainActor
    static func conflict(for chord: HotKeyChord, excluding: HotKeyOwnerID) -> HotKeyOwnerID? {
        for owner in allCases where owner != excluding {
            if owner.currentChord == chord {
                return owner
            }
        }
        return nil
    }
}
