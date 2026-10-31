import Combine
import Foundation

/// 设置深链：空态岛「去添加」与菜单栏共用。
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    @Published var section: SettingsSection = .island
    /// 变化时打开/前置设置窗。
    @Published private(set) var openToken = UUID()

    private init() {}

    func open(_ section: SettingsSection) {
        self.section = section
        openToken = UUID()
        AppLog.info("Settings", "请求打开设置", ["section": section.rawValue])
        NotificationCenter.default.post(name: .ridgeOpenSettings, object: nil)
    }
}

extension Notification.Name {
    static let ridgeOpenSettings = Notification.Name("app.daphnis.Ridge.openSettings")
}
