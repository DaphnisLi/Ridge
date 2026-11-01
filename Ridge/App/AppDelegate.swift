import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let island = IslandController()
    private let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("Overlay", "Ridge 启动", [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        ])
        island.start()
        menuBar.start(island: island)
        // 日历服务随会议小组件启动；此处再兜底一次，便于已授权时尽早拉数。
        MeetingCalendarService.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MeetingCalendarService.shared.stop()
        island.stop()
        AppLog.info("Overlay", "Ridge 即将退出")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
