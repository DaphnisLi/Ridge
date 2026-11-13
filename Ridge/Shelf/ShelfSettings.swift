import Combine
import Foundation

/// 货架模块偏好；「已复制」总开关迁到小组件库 `builtin.copiedNotice`。
@MainActor
final class ShelfSettings: ObservableObject {
    static let shared = ShelfSettings()

    private enum Key {
        static let showCopiedNoticeLegacy = "shelf.showCopiedNotice.v1"
        static let copiedNoticeMigrated = "shelf.copiedNotice.migratedToWidget.v1"
        static let magneticDropCapture = "shelf.magneticDropCapture.v1"
    }

    /// 磁吸双舱：开启时拖文件进接近区弹出暂存 / 隔空传送；关闭后无双舱与隔空，但仍用同一拖文件接近区入普通货架。
    @Published var magneticDropCaptureEnabled: Bool {
        didSet {
            guard magneticDropCaptureEnabled != oldValue else { return }
            UserDefaults.standard.set(magneticDropCaptureEnabled, forKey: Key.magneticDropCapture)
            AppLog.info("Shelf", "磁吸拖放已更新", ["enabled": magneticDropCaptureEnabled])
            if !magneticDropCaptureEnabled {
                ShelfDropSession.shared.setActive(false, reason: "magneticDisabled")
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.magneticDropCapture) == nil {
            magneticDropCaptureEnabled = true
        } else {
            magneticDropCaptureEnabled = defaults.bool(forKey: Key.magneticDropCapture)
        }
        migrateCopiedNoticeWidgetGateIfNeeded()
    }

    /// 复制成功是否上岛：读小组件库 `builtin.copiedNotice` 开关。
    var showCopiedNotice: Bool {
        ClipboardCopiedNoticeGate.isTipEnabled
    }

    func restoreMagneticDropDefaults() {
        magneticDropCaptureEnabled = true
        AppLog.info("Shelf", "磁吸拖放已恢复默认", ["enabled": true])
    }

    /// 把旧货架嵌套开关迁到 `builtin.copiedNotice`（只跑一次）。
    func migrateCopiedNoticeWidgetGateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.copiedNoticeMigrated) else { return }
        if let legacy = defaults.object(forKey: Key.showCopiedNoticeLegacy) as? Bool, !legacy {
            WidgetSettings.shared.setEnabled(ClipboardCopiedNoticeGate.widgetID, enabled: false)
            AppLog.info("Shelf", "已复制提示：旧关状态已迁到小组件库")
        } else {
            // 旧默认开启 / 无键：显式打开 tip，并立刻按 tip 拉起剪贴板监听。
            WidgetSettings.shared.setEnabled(ClipboardCopiedNoticeGate.widgetID, enabled: true)
            AppLog.debug("Shelf", "已复制提示：沿用默认开启并同步监听")
        }
        defaults.set(true, forKey: Key.copiedNoticeMigrated)
        ClipboardCopiedNoticeGate.syncClipboardMonitoring(reason: "copiedNoticeMigrate")
    }
}
