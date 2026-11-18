#if DEBUG
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
        FocusTimerSession.shared.debugAdvance(byMinutes: minutes)
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
        let notice = ProjectWatchEndedNotice(
            id: "projects.watch.debug.\(UUID().uuidString.prefix(8))",
            projectName: "Ridge Lab",
            label: success ? "lab-ok" : "lab-fail",
            message: success ? L10n.TestLab.processEndedSuccess : L10n.TestLab.processEndedFailure,
            endedAt: Date(),
            outcome: success ? .succeeded : .failed(code: 1),
            logPath: nil,
            peakMemoryBytes: 48 * 1024 * 1024,
            durationSeconds: 12
        )
        IslandNoticeCenter.shared.present(.processEnded(notice))
        note(success ? L10n.TestLab.statusProcessTipOK : L10n.TestLab.statusProcessTipFail)
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
}
#endif
