import Combine
import Foundation

/// 设置深链：空态岛「去添加」与菜单栏共用。
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    @Published var section: SettingsSection = .island
    /// 变化时打开/前置设置窗。
    @Published private(set) var openToken = UUID()
    /// 打开设置后跳进指定小组件预览（由 WidgetsSettingsPane 消费）。
    @Published private(set) var pendingWidgetPreviewID: WidgetID?

    private init() {}

    func open(_ section: SettingsSection) {
        self.section = section
        pendingWidgetPreviewID = nil
        openToken = UUID()
        AppLog.info("Settings", "请求打开设置", ["section": section.rawValue])
        NotificationCenter.default.post(name: .ridgeOpenSettings, object: nil)
    }

    /// 打开「小组件」并进入某个小组件预览页（如会议配置）。
    func openWidgetPreview(_ id: WidgetID) {
        section = .widgets
        pendingWidgetPreviewID = id
        openToken = UUID()
        AppLog.info("Settings", "请求打开小组件预览", ["id": id])
        NotificationCenter.default.post(name: .ridgeOpenSettings, object: nil)
    }

    func consumePendingWidgetPreview() -> WidgetID? {
        let id = pendingWidgetPreviewID
        pendingWidgetPreviewID = nil
        return id
    }
}

extension Notification.Name {
    static let ridgeOpenSettings = Notification.Name("app.daphnis.Ridge.openSettings")
    /// 今日击键桶有更新（峰值时段可能变化）。
    static let ridgeResourceKeystrokesDidChange = Notification.Name(
        "app.daphnis.Ridge.resourceKeystrokesDidChange"
    )
}
