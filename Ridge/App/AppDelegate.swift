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
        IslandNoticeCenter.shared.dismiss(id: "resource.ram.debug.sticky")
        IslandNoticeCenter.shared.dismiss(id: "projects.watch.debug.sticky")

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
        if WidgetSettings.shared.isEnabled(MacBatteryTipWidget.manifest.id) {
            MacBatterySession.shared.start()
        }
        if WidgetSettings.shared.isEnabled(NetworkLinkTipWidget.manifest.id) {
            NetworkLinkSession.shared.start()
        }
        if WidgetSettings.shared.isEnabled(SystemFocusTipWidget.manifest.id) {
            SystemFocusSession.shared.start()
        }
        if WidgetSettings.shared.isEnabled(DownloadCompleteTipWidget.manifest.id) {
            DownloadCompleteSession.shared.start()
        }
        LoginItemService.shared.refresh()
        UpdateService.shared.start()
        // 待引导时尽早提成 regular，否则延迟出窗时仍是 accessory，易被其它 App 盖住。
        OnboardingController.shared.prepareActivationPolicyIfNeeded()
        // 首次启动引导：下一拍再出，避免与岛初始化抢主线程。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            OnboardingController.shared.presentIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 从系统设置授权返回 / Dock 点回时再钉引导窗，避免仍被设置或其它 App 盖住。
        OnboardingController.shared.reassertFrontIfNeeded(reason: "appDidBecomeActive")
    }

    func applicationWillResignActive(_ notification: Notification) {
        // 系统设置 / 授权框抢前台时，引导窗主动让路，勿用浮动层压住它们。
        OnboardingController.shared.yieldFrontForSystemUI(reason: "appWillResignActive")
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
