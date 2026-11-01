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
        // 日历 / Now Playing 随 App 常驻；有内容时再 nudge 对应小组件上岛。
        MeetingCalendarService.shared.start()
        NowPlayingService.shared.start()
        SoundSession.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SoundSession.shared.stop()
        NowPlayingService.shared.stop()
        MeetingCalendarService.shared.stop()
        island.stop()
        AppLog.info("Overlay", "Ridge 即将退出")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
