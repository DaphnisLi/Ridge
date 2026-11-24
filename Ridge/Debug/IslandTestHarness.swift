#if DEBUG
import Darwin
import Foundation

/// 岛测试台中枢：编排专注快进、会议播种、进程、外设、控制台与组合剧本。
@MainActor
final class IslandTestHarness: ObservableObject {
    static let shared = IslandTestHarness()

    @Published private(set) var statusMessage: String = ""
    @Published private(set) var lastLaunchedPID: Int32?
    @Published var selectedMeetingPlatform: MeetingPlatform = .zoom
    @Published var selectedMeetingUrgency: MeetingLeadUrgency = .warning

    private init() {}

    // MARK: - Status

    func note(_ message: String) {
        statusMessage = message
        AppLog.info("TestLab", message)
    }

    /// 一键清掉测试台留下的运行时数据（tip / 假媒体 / 外设注入 / 监视 / 测试会议 / 专注快进等）。
    func clearAllTestData() {
        AppLog.warn("TestLab", "一键清除测试数据开始")

        IslandNoticeCenter.shared.dismiss(id: nil)
        MeetingLeadSession.shared.publish(nil, reason: "testLabClearAll")

        setFakeMediaPlaying(false)
        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testLabClearAll")

        BatterySession.shared.debugClearInjectedDevices()

        FocusTimerSession.shared.debugEnterPicking()
        FocusTimerSession.shared.dismissCompletion()

        let projects = ProjectReleaseSession.shared
        for watch in projects.watches {
            projects.stopWatch(watch)
        }
        projects.dismissWatchEnded()

        if let pid = lastLaunchedPID {
            _ = kill(pid, SIGTERM)
            lastLaunchedPID = nil
            AppLog.info("TestLab", "已向测试进程发 SIGTERM", ["pid": pid])
        }

        do {
            let n = try IslandTestLabMeetingSeeder.cleanupAll()
            AppLog.info("TestLab", "已清理测试日历会议", ["count": n])
        } catch {
            AppLog.warn("TestLab", "清理测试会议失败", ["error": error.localizedDescription])
        }

        IslandTestLabSettings.shared.resetTipDuration()
        IslandController.shared?.collapse(reason: "testLabClearAll")

        note(L10n.TestLab.statusClearedAll)
        AppLog.warn("TestLab", "一键清除测试数据完成")
    }

    // MARK: - Media demo

    func setFakeMediaPlaying(_ on: Bool) {
        NowPlayingService.shared.setOnboardingDemoActive(on)
        if on {
            LiveIslandGate.shared.admit(LiveIslandGate.mediaID, reason: "testLabMedia")
        } else {
            LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testLabMediaOff")
        }
        note(on ? L10n.TestLab.statusFakeMediaOn : L10n.TestLab.statusFakeMediaOff)
    }

    // MARK: - Focus

    func ensureFocusEnabled() {
        let id = FocusTimerWidget.manifest.id
        WidgetSettings.shared.setEnabled(id, enabled: true)
        FocusTimerSession.shared.setWidgetEnabled(true)
    }

    func focusEnterRunning(minutes: Int = 25) {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugEnterRunning(minutes: minutes)
        note(L10n.TestLab.statusFocusRunning(minutes))
    }

    func focusEnterOvertime() {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugEnterOvertime()
        note(L10n.TestLab.statusFocusOvertime)
    }

    func focusEnterCompleted() {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugEnterCompleted()
        note(L10n.TestLab.statusFocusCompleted)
    }

    func focusAdvance(byMinutes minutes: Int) {
        ensureFocusEnabled()
        let session = FocusTimerSession.shared
        // 倒计时工具：若不在倒计时态，先进入计时再快进。
        if session.phase != .running && session.phase != .overtime {
            session.debugEnterRunning(minutes: 25)
        }
        session.debugAdvance(byMinutes: minutes)
        note(L10n.TestLab.statusFocusAdvance(minutes))
    }

    func focusJumpToRemaining(seconds: Int) {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugJumpToRemaining(seconds: seconds)
        note(L10n.TestLab.statusFocusRemain(seconds))
    }

    func focusJumpToEnd() {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugJumpToEnd()
        note(L10n.TestLab.statusFocusEnded)
    }

    func focusJumpIntoOvertime() {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugJumpIntoOvertime()
        note(L10n.TestLab.statusFocusOvertime)
    }

    func focusEnterCountUp(elapsedSeconds: Int = 90) {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugEnterCountUp(elapsedSeconds: elapsedSeconds)
        IslandController.shared?.collapse(reason: "testLabFocusCountUp")
        note(L10n.TestLab.statusFocusCountUp)
    }

    /// 正计时加时：不在正计时态时先进入，再加分钟。
    func focusCountUpAdvance(byMinutes minutes: Int) {
        ensureFocusEnabled()
        let session = FocusTimerSession.shared
        if session.phase != .countUp {
            session.debugEnterCountUp(elapsedSeconds: session.snapshot.elapsedSeconds)
            IslandController.shared?.collapse(reason: "testLabFocusCountUp")
        }
        session.debugAdvance(byMinutes: minutes)
        note(L10n.TestLab.statusFocusCountUpAdvance(minutes))
    }

    func focusCountUpAdvance(byHours hours: Int) {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugAdvanceCountUp(byHours: hours)
        IslandController.shared?.collapse(reason: "testLabFocusCountUp")
        note(L10n.TestLab.statusFocusCountUpAdvanceHours(hours))
    }

    func focusCountUpTogglePause() {
        ensureFocusEnabled()
        let session = FocusTimerSession.shared
        if session.phase != .countUp {
            session.debugEnterCountUp(elapsedSeconds: 90)
            IslandController.shared?.collapse(reason: "testLabFocusCountUp")
        }
        session.toggleCountUpPause()
        note(
            session.snapshot.isPaused
                ? L10n.TestLab.statusFocusCountUpPaused
                : L10n.TestLab.statusFocusCountUpResumed
        )
    }

    func focusCountUpFinish() {
        ensureFocusEnabled()
        let session = FocusTimerSession.shared
        if session.phase != .countUp {
            session.debugEnterCountUp(elapsedSeconds: 90)
        }
        session.finishEarly()
        note(L10n.TestLab.statusFocusEnded)
    }

    // MARK: - Meeting

    func createSelectedMeeting() {
        Task {
            if MeetingCalendarService.shared.authStatus != .authorized {
                _ = await MeetingCalendarService.shared.requestAccess()
            }
            do {
                _ = try IslandTestLabMeetingSeeder.createMeeting(
                    platform: selectedMeetingPlatform,
                    urgency: selectedMeetingUrgency
                )
                note(L10n.TestLab.statusMeetingCreated(
                    selectedMeetingPlatform.displayName,
                    selectedMeetingUrgency.stageTitle
                ))
            } catch {
                note(error.localizedDescription)
            }
        }
    }

    func cleanupMeetings() {
        do {
            let n = try IslandTestLabMeetingSeeder.cleanupAll()
            note(L10n.TestLab.statusMeetingCleaned(n))
        } catch {
            note(error.localizedDescription)
        }
    }

    // MARK: - Process

    func launchSleepAndWatch(seconds: Int = 12) {
        do {
            let launched = try IslandTestLabProcessLauncher.launchSleep(seconds: seconds)
            lastLaunchedPID = launched.pid
            ProjectReleaseSession.shared.debugStartWatch(
                pid: launched.pid,
                label: launched.label,
                projectName: "Ridge Lab"
            )
            ControlDeckSettings.shared.setModuleEnabled("projects", true)
            note(L10n.TestLab.statusProcessWatching(Int(launched.pid), seconds))
        } catch {
            note(error.localizedDescription)
        }
    }

    func launchDockerAndWatch(seconds: Int = 15) {
        do {
            let launched = try IslandTestLabProcessLauncher.launchDockerSleep(seconds: seconds)
            lastLaunchedPID = launched.pid
            ProjectReleaseSession.shared.debugStartWatch(
                pid: launched.pid,
                label: launched.label,
                projectName: "Ridge Lab"
            )
            ControlDeckSettings.shared.setModuleEnabled("projects", true)
            note(L10n.TestLab.statusProcessWatching(Int(launched.pid), seconds))
        } catch {
            note(error.localizedDescription)
        }
    }

    func presentProcessEndedTip(success: Bool) {
        presentProcessEndedTip(outcome: success ? .succeeded : .failed(code: 1))
    }

    func presentProcessEndedTip(outcome: ProjectWatchOutcome) {
        let (label, message): (String, String) = {
            switch outcome {
            case .succeeded:
                return ("lab-ok", L10n.TestLab.processEndedSuccess)
            case .failed:
                return ("lab-fail", L10n.TestLab.processEndedFailure)
            case .signaled:
                return ("lab-sig", L10n.TestLab.processEndedFailure)
            case .unknown:
                return ("lab-unk", L10n.TestLab.processEndedFailure)
            }
        }()
        let notice = ProjectWatchEndedNotice(
            id: "projects.watch.debug.\(UUID().uuidString.prefix(8))",
            projectName: "Ridge Lab",
            label: label,
            message: message,
            endedAt: Date(),
            outcome: outcome,
            logPath: nil,
            peakMemoryBytes: 48 * 1024 * 1024,
            durationSeconds: 12
        )
        IslandNoticeCenter.shared.present(.processEnded(notice))
        note(L10n.TestLab.statusProcessTip(outcomeLabel(outcome)))
    }

    private func outcomeLabel(_ outcome: ProjectWatchOutcome) -> String {
        switch outcome {
        case .succeeded: return L10n.TestLab.galleryProcessOK
        case .failed: return L10n.TestLab.galleryProcessFail
        case .signaled: return L10n.TestLab.galleryProcessSignal
        case .unknown: return L10n.TestLab.galleryProcessFail
        }
    }

    // MARK: - Peripheral

    func injectPeripheralDevice(kind: BatteryDeviceKind, percent: Int?, isLow: Bool) {
        BatterySession.shared.debugInjectDevice(
            name: "Lab \(kind.rawValue)",
            kind: kind,
            percent: percent,
            isLow: isLow
        )
        ControlDeckSettings.shared.setModuleEnabled("battery", true)
        note(L10n.TestLab.statusPeripheralInjected(kind.rawValue, percent ?? -1))
    }

    func clearPeripheralInjects() {
        BatterySession.shared.debugClearInjectedDevices()
        note(L10n.TestLab.statusPeripheralCleared)
    }

    func presentPeripheralTip(style: PeripheralTipStyle) {
        let notice: BatteryPeripheralNotice
        let payload: IslandNoticePayload
        switch style {
        case .low:
            notice = BatteryPeripheralNotice(
                id: "battery.low.debug.\(UUID().uuidString.prefix(6))",
                deviceID: "lab.mouse",
                deviceName: L10n.Battery.tipSampleMouse,
                kind: .mouse,
                percent: 12,
                threshold: BatterySettings.shared.lowThresholdPercent,
                detail: L10n.Battery.lowNoticeDetail(12, BatterySettings.shared.lowThresholdPercent)
            )
            payload = .peripheralLowBattery(notice)
        case .full:
            notice = BatteryPeripheralNotice(
                id: "battery.full.debug.\(UUID().uuidString.prefix(6))",
                deviceID: "lab.keyboard",
                deviceName: L10n.Battery.tipSampleKeyboard,
                kind: .keyboard,
                percent: 100,
                threshold: 100,
                detail: L10n.Battery.fullNoticeDetail
            )
            payload = .peripheralFullCharge(notice)
        case .connect:
            notice = BatteryPeripheralNotice(
                id: "battery.connect.debug.\(UUID().uuidString.prefix(6))",
                deviceID: "lab.headphones",
                deviceName: L10n.PeripheralTip.tipSampleHeadphones,
                kind: .headphones,
                percent: 86,
                threshold: 0,
                detail: L10n.PeripheralTip.connectNoticeDetail
            )
            payload = .peripheralConnected(notice)
        }
        IslandNoticeCenter.shared.present(payload)
        note(L10n.TestLab.statusPeripheralTip(style.rawValue))
    }

    enum PeripheralTipStyle: String {
        case low, full, connect
    }

    func presentMacBatteryTip(kind: MacBatteryNotice.Kind) {
        MacBatterySession.shared.presentSample(kind: kind)
        note(L10n.TestLab.statusMacBatteryTip(kind.rawValue))
    }

    func presentNetworkLinkTip(kind: NetworkLinkTipKind) {
        var notice = NetworkLinkNoticeCard.previewNotice(kind: kind)
        notice = NetworkLinkNotice(
            id: "test.network.\(kind.rawValue).\(UUID().uuidString.prefix(6))",
            kind: notice.kind,
            title: notice.title,
            detail: notice.detail,
            ssid: notice.ssid,
            latencyMs: notice.latencyMs
        )
        let payload: IslandNoticePayload
        switch kind {
        case .wifiConnected: payload = .networkWifiConnected(notice)
        case .wiredConnected: payload = .networkWiredConnected(notice)
        case .vpnConnected: payload = .networkVPNConnected(notice)
        case .wifiDisconnected: payload = .networkWifiDisconnected(notice)
        case .vpnDisconnected: payload = .networkVPNDisconnected(notice)
        }
        IslandNoticeCenter.shared.present(payload)
        note(L10n.TestLab.statusNetworkLinkTip(kind.rawValue))
        AppLog.info("TestLab", "已投递网络 tip", ["kind": kind.rawValue])
    }

    func presentSystemFocusTip(kind: SystemFocusTipKind) {
        SystemFocusSession.shared.presentSample(kind: kind)
        note(L10n.TestLab.statusSystemFocusTip(kind.rawValue))
    }

    func presentDownloadCompleteSample() {
        DownloadCompleteSession.shared.presentSample()
        note(L10n.TestLab.statusDownloadComplete)
    }

    func presentAirDropReceiveSample() {
        AirDropReceiveSession.shared.presentSample()
        note(L10n.AirDropReceive.tipTitle)
    }

    func presentDownloadDownloadingSample() {
        DownloadCompleteSession.shared.presentDownloadingSample()
        note(L10n.TestLab.statusDownloadDownloading)
    }

    func presentDownloadForceCompleteSample() {
        DownloadCompleteSession.shared.presentForceCompleteFromDownloading()
        note(L10n.TestLab.statusDownloadComplete)
    }

    func clearDownloadCompleteSample() {
        DownloadCompleteSession.shared.clearPending(reason: "testLabClear")
        note(L10n.TestLab.statusDownloadCleared)
    }

    // MARK: - Control deck

    func openControlDeck(pane: ControlDeckSettings.Pane) {
        ControlDeckSettings.shared.setModuleEnabled(pane.rawValue, true)
        ControlDeckSettings.shared.activePane = pane
        WidgetRuntime.shared.focusControlDeck(pane: pane)
        IslandController.shared?.expand(reason: "testLabDeck")
        note(L10n.TestLab.statusDeckOpened(pane.title))
    }

    // MARK: - Combos

    func comboMediaPlusFocus() {
        setFakeMediaPlaying(true)
        focusEnterRunning(minutes: 25)
        focusJumpToRemaining(seconds: 90)
        note(L10n.TestLab.statusComboMediaFocus)
    }

    func comboMediaFocusPlusC() {
        comboMediaPlusFocus()
        presentProcessEndedTip(success: true)
        note(L10n.TestLab.statusComboMediaFocusC)
    }

    // MARK: - 全状态上岛（真岛投递）

    func focusEnterPicking() {
        ensureFocusEnabled()
        FocusTimerSession.shared.debugEnterPicking()
        note(L10n.TestLab.statusFocusPicking)
    }

    func presentMeetingTip(urgency: MeetingLeadUrgency) {
        WidgetSettings.shared.setEnabled(MeetingCountdownWidget.manifest.id, enabled: true)
        MeetingLeadSession.shared.debugPresentSample(urgency: urgency)
        note(L10n.TestLab.statusMeetingTip(urgency.stageTitle))
    }

    func focusApplyPreviewTab(_ tab: FocusTimerPreviewTab) {
        switch tab {
        case .standby:
            focusEnterRunning(minutes: 25)
            IslandController.shared?.collapse(reason: "testLabFocusStandby")
            note(L10n.TestLab.statusFocusStandby)
        case .picking:
            focusEnterPicking()
            IslandController.shared?.expand(reason: "testLabFocusPicking")
        case .overtime:
            focusEnterOvertime()
            IslandController.shared?.collapse(reason: "testLabFocusOvertime")
            note(L10n.TestLab.statusFocusOvertime)
        case .countUp:
            focusEnterCountUp(elapsedSeconds: 1 * 3600 + 27 * 60 + 32)
        case .completed:
            focusEnterCompleted()
            IslandController.shared?.expand(reason: "testLabFocusCompleted")
        }
    }

    func presentMediaStandby() {
        WidgetSettings.shared.setEnabled(MediaNowPlayingWidget.manifest.id, enabled: true)
        setFakeMediaPlaying(true)
        IslandController.shared?.collapse(reason: "testLabMediaStandby")
        note(L10n.TestLab.statusMediaStandby)
    }

    func presentMediaExpanded() {
        WidgetSettings.shared.setEnabled(MediaNowPlayingWidget.manifest.id, enabled: true)
        setFakeMediaPlaying(true)
        WidgetRuntime.shared.focusForSettings(MediaNowPlayingWidget.manifest.id)
        IslandController.shared?.expand(reason: "testLabMediaExpanded")
        note(L10n.TestLab.statusMediaExpanded)
    }

    func presentAITip(stage: AIUsageStage) {
        WidgetSettings.shared.setEnabled(AIUsageWidget.manifest.id, enabled: true)
        let settings = AIUsageSettings.shared
        let remaining: Int
        let resetOffset: TimeInterval
        switch stage {
        case .abundant:
            remaining = settings.abundantThreshold
            resetOffset = 14 * 86_400
        case .warning:
            remaining = settings.warningThreshold
            resetOffset = 9 * 3600
        case .critical:
            remaining = settings.criticalThreshold
            resetOffset = 47 * 60
        case .unknown:
            remaining = 0
            resetOffset = 3600
        }
        let id = "aiUsage.lab.\(stage.rawValue).\(UUID().uuidString.prefix(6))"
        IslandNoticeCenter.shared.present(
            .aiUsageAlert(
                id: id,
                providerName: L10n.AIUsage.providerCursor,
                remainingPercent: remaining,
                stage: stage,
                resetsAt: Date().addingTimeInterval(resetOffset)
            )
        )
        note(L10n.TestLab.statusAITip(stage.label))
    }

    func presentMoveReminderTip() {
        WidgetSettings.shared.setEnabled("builtin.moveReminder", enabled: true)
        let settings = MoveReminderSettings.shared
        let notice = MoveReminderSession.Notice(
            id: "moveReminder.lab.\(UUID().uuidString.prefix(6))",
            activeMinutes: settings.activeTriggerMinutes,
            restMinutes: settings.suggestedRestMinutes
        )
        IslandNoticeCenter.shared.present(.moveReminder(notice))
        note(L10n.TestLab.statusMoveTip)
    }

    func presentRAMTip() {
        let notice = ResourceRAMPressureNotice(
            id: "resource.ram.lab.\(UUID().uuidString.prefix(6))",
            ramUsedBytes: 28_000_000_000,
            ramPercent: 96,
            topAppName: "Xcode",
            topAppBundleID: "com.apple.dt.Xcode",
            topAppMemoryBytes: 4_200_000_000
        )
        IslandNoticeCenter.shared.present(.ramPressure(notice))
        note(L10n.TestLab.statusRAMTip)
    }

    func presentCopiedTip() {
        WidgetSettings.shared.setEnabled(ClipboardCopiedNoticeGate.widgetID, enabled: true)
        let tipID = "copy.text.lab.\(UUID().uuidString)"
        IslandNoticeCenter.shared.present(
            .clipboardCaptureHint(
                id: tipID,
                text: L10n.Shelf.copied,
                symbol: "text.alignleft"
            )
        )
        note(L10n.TestLab.statusCopiedTip)
    }

    func presentColorPickTip() {
        WidgetSettings.shared.setEnabled("builtin.colorPick", enabled: true)
        IslandNoticeCenter.shared.present(.colorPickTip)
        note(L10n.TestLab.statusColorPickTip)
    }

    func presentOCRTip() {
        WidgetSettings.shared.setEnabled("builtin.ocrSelect", enabled: true)
        IslandNoticeCenter.shared.present(.ocrSelectTip)
        note(L10n.TestLab.statusOCRTip)
    }

    func dismissManualTips() {
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.colorPickTipID)
        IslandNoticeCenter.shared.dismiss(id: IslandNoticePayload.ocrSelectTipID)
        note(L10n.TestLab.statusManualTipsDismissed)
    }

    func openPanelWidget(id: WidgetID, title: String) {
        WidgetSettings.shared.setEnabled(id, enabled: true)
        WidgetRuntime.shared.focusForSettings(id)
        IslandController.shared?.expand(reason: "testLabPanel:\(id)")
        note(L10n.TestLab.statusPanelOpened(title))
    }
}
#endif
