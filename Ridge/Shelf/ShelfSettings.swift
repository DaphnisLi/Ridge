import Combine
import Foundation

/// 货架模块偏好；「已复制」总开关迁到小组件库 `builtin.copiedNotice`。
@MainActor
final class ShelfSettings: ObservableObject {
    static let shared = ShelfSettings()

    private enum Key {
        static let showCopiedNoticeLegacy = "shelf.showCopiedNotice.v1"
        static let copiedNoticeMigrated = "shelf.copiedNotice.migratedToWidget.v1"
    }

    private init() {
        migrateCopiedNoticeWidgetGateIfNeeded()
    }

    /// 复制成功是否上岛：读小组件库 `builtin.copiedNotice` 开关。
    var showCopiedNotice: Bool {
        WidgetSettings.shared.isEnabled(Self.copiedNoticeWidgetID)
    }

    private static let copiedNoticeWidgetID: WidgetID = "builtin.copiedNotice"

    /// 把旧货架嵌套开关迁到 `builtin.copiedNotice`（只跑一次）。
    func migrateCopiedNoticeWidgetGateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.copiedNoticeMigrated) else { return }
        if let legacy = defaults.object(forKey: Key.showCopiedNoticeLegacy) as? Bool, !legacy {
            WidgetSettings.shared.setEnabled(Self.copiedNoticeWidgetID, enabled: false)
            AppLog.info("Shelf", "已复制提示：旧关状态已迁到小组件库")
        } else {
            AppLog.debug("Shelf", "已复制提示：沿用小组件库默认开启")
        }
        defaults.set(true, forKey: Key.copiedNoticeMigrated)
    }
}
