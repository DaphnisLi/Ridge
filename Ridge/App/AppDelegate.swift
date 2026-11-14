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
        for stage in ["abundant", "warning", "critical"] {
            IslandNoticeCenter.shared.dismiss(id: "aiUsage.debug.\(stage)")
        }
        IslandNoticeCenter.shared.dismiss(id: "moveReminder.debug.sticky")

        island.start()
        menuBar.start(island: island)
        // Now Playing 无 TCC；日历 / 混音等有权限需求的会话按小组件开关再 start。
        NowPlayingService.shared.start()
        if WidgetSettings.shared.isEnabled("builtin.meeting") {
            MeetingCalendarService.shared.start()
        }
        if ControlDeckSettings.shared.isModuleEnabled("volume") {
            SoundSession.shared.start()
        }
        // 资源监控：系统采样 + 焦点；击键须进「专注与击键」页或授权后才装 tap。
        ResourceMonitorSession.shared.start()
        if WidgetSettings.shared.isEnabled("builtin.aiUsage") {
            AIUsageSession.shared.start()
        }
        if WidgetSettings.shared.isEnabled("builtin.moveReminder") {
            MoveReminderSession.shared.start()
        }
        LoginItemService.shared.refresh()
        UpdateService.shared.start()
        // 首次启动引导：下一拍再出，避免与岛初始化抢主线程。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            OnboardingController.shared.presentIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if WidgetSettings.shared.isEnabled("builtin.moveReminder") {
            MoveReminderSession.shared.stop()
        }
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
