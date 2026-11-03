import SwiftUI

@main
struct RidgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 占位 Scene：真正设置窗由 MenuBarController 管理（固定 1200×620）。
        // App 菜单「设置…」/ ⌘, 不得再走系统 Settings 小窗，否则尺寸不一致。
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.Common.settings) {
                    NotificationCenter.default.post(name: .ridgeOpenSettings, object: nil)
                    AppLog.info("Settings", "App 菜单打开设置（统一大窗）")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
