import Foundation

/// 「已复制」上岛闸门：库内 tip `builtin.copiedNotice` 总开关；剪贴板轮询不依赖货架面板。
enum ClipboardCopiedNoticeGate {
    static let widgetID: WidgetID = "builtin.copiedNotice"

    /// 货架开着，或独立 tip 开着 → 需要轮询系统剪贴板。
    /// 拆 tip 后若仍绑死货架模块，关货架会停监听，复制再也不上岛（shelf-copied-notice-miss）。
    static func shouldMonitorPasteboard(shelfEnabled: Bool, tipEnabled: Bool) -> Bool {
        shelfEnabled || tipEnabled
    }

    @MainActor
    static var isTipEnabled: Bool {
        WidgetSettings.shared.isEnabled(widgetID)
    }

    @MainActor
    static var shouldMonitorPasteboard: Bool {
        shouldMonitorPasteboard(
            shelfEnabled: ControlDeckSettings.shared.isModuleEnabled("shelf"),
            tipEnabled: isTipEnabled
        )
    }

    /// 按当前货架 / tip 开关对齐 `ClipboardHistoryStore` 监听。
    @MainActor
    static func syncClipboardMonitoring(reason: String) {
        let shelfOn = ControlDeckSettings.shared.isModuleEnabled("shelf")
        let tipOn = isTipEnabled
        let should = shouldMonitorPasteboard(shelfEnabled: shelfOn, tipEnabled: tipOn)
        if should {
            ClipboardHistoryStore.shared.start()
            AppLog.info("Clipboard", "剪贴板监听保持开启", [
                "reason": reason,
                "shelf": shelfOn,
                "copiedTip": tipOn
            ])
        } else {
            ClipboardHistoryStore.shared.stop()
            AppLog.info("Clipboard", "剪贴板监听已停止", [
                "reason": reason,
                "shelf": shelfOn,
                "copiedTip": tipOn
            ])
        }
    }
}
