import Foundation

/// Runtime 内部实现的 Context；对外只暴露 `WidgetContext`。
@MainActor
final class WidgetContextImpl: WidgetContext {
    let widgetID: WidgetID
    private weak var runtime: WidgetRuntime?

    init(widgetID: WidgetID, runtime: WidgetRuntime) {
        self.widgetID = widgetID
        self.runtime = runtime
    }

    func requestDisplay() {
        runtime?.requestDisplay(widgetID)
    }

    func withdrawDisplay() {
        runtime?.withdrawDisplay(widgetID)
    }

    func openSettings() {
        SettingsNavigator.shared.open(.widgets)
    }

    func log(_ message: String, fields: [String: Any] = [:]) {
        var merged = fields
        merged["widget"] = widgetID
        AppLog.debug("Widget", message, merged)
    }

    func storageKey(_ name: String) -> String {
        "widget.\(widgetID).\(name)"
    }
}
