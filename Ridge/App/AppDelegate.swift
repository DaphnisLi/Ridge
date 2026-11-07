import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let island = IslandController()
    private let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.warn("Overlay", "Ridge 启动", [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        ])
        // 清掉额度 / 久坐调试常驻，避免挡住正常瞬时通知。
        UserDefaults.standard.removeObject(forKey: "aiUsage.debugStickyWarning")
        UserDefaults.standard.removeObject(forKey: "aiUsage.debugForceWarning")
        UserDefaults.standard.removeObject(forKey: "aiUsage.debugStage")
        UserDefaults.standard.removeObject(forKey: "moveReminder.debugSticky")
        IslandNoticeCenter.shared.dismiss(id: "aiUsage.debug.warning")
        IslandNoticeCenter.shared.dismiss(id: "moveReminder.debug.sticky")

        island.start()
        menuBar.start(island: island)
        // 日历 / Now Playing 随 App 常驻；有内容时再 nudge 对应小组件上岛。
        MeetingCalendarService.shared.start()
        NowPlayingService.shared.start()
        SoundSession.shared.start()
        // 资源监控：系统采样 + 焦点；击键在有输入监控权限时生效。
        ResourceMonitorSession.shared.start()
        // AI 额度：后台感知；仅触阈时走瞬时通知。
        AIUsageSession.shared.start()
        // 久坐起身：HID 空闲累计；触阈时走瞬时通知（须用户点稍后 / 今天不再才收）。
        MoveReminderSession.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MoveReminderSession.shared.stop()
        ResourceMonitorSession.shared.stop()
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
