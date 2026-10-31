import SwiftUI

@main
struct RidgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 无主窗口；设置由菜单栏打开居中大窗。
        Settings {
            SettingsRootView(settings: IslandSettings.shared)
                .frame(minWidth: 860, minHeight: 560)
        }
    }
}
