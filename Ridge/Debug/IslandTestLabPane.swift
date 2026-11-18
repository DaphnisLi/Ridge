#if DEBUG
import SwiftUI

/// 设置侧栏「岛测试台」：仅 DEBUG 编译；Release 无入口。
struct IslandTestLabPane: View {
    @ObservedObject private var labSettings = IslandTestLabSettings.shared
    @ObservedObject private var harness = IslandTestHarness.shared
    @ObservedObject private var focus = FocusTimerSession.shared
    @ObservedObject private var meeting = MeetingCalendarService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                header

                tipDurationCard
                mediaCard
                focusCard
                meetingCard
                processCard
                peripheralCard
                controlDeckCard
                comboCard

                if !harness.statusMessage.isEmpty {
                    statusBanner
                }
            }
            .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
            .padding(.vertical, SettingsChrome.Spacing.stack)
        }
        .background(SettingsChrome.pageBackground)
        .onAppear {
            AppLog.info("TestLab", "测试台页已显示")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.TestLab.pageTitle)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.TestLab.pageSubtitle)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBanner: some View {
        SettingsCard {
            Text(harness.statusMessage)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Tip duration

    private var tipDurationCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.tipDurationTitle, symbol: "timer")
                Text(L10n.TestLab.tipDurationSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                SettingsSwitchRow(
                    title: L10n.TestLab.tipOverrideSwitch,
                    subtitle: L10n.TestLab.tipOverrideHint,
                    isOn: $labSettings.tipOverrideEnabled
                )
                if labSettings.tipOverrideEnabled {
                    SettingsSliderRow(
                        title: L10n.TestLab.tipSecondsLabel,
                        valueText: String(format: "%.1fs", labSettings.tipSeconds),
                        value: $labSettings.tipSeconds,
                        range: 0.5...30,
                        step: 0.5,
                        leading: "0.5s",
                        trailing: "30s"
                    )
                }
                Button(L10n.TestLab.tipReset) {
                    labSettings.resetTipDuration()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: Media

    private var mediaCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.mediaTitle, symbol: "music.note")
                Text(L10n.TestLab.mediaSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                HStack(spacing: 8) {
                    labButton(L10n.TestLab.mediaFakeOn) { harness.setFakeMediaPlaying(true) }
                    labButton(L10n.TestLab.mediaFakeOff) { harness.setFakeMediaPlaying(false) }
                }
            }
        }
    }

    // MARK: Focus

    private var focusCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.focusTitle, symbol: "timer.circle")
                Text(L10n.TestLab.focusSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Text(focusPhaseLine)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                flowWrap([
                    (L10n.TestLab.focusEnterRunning, { harness.focusEnterRunning(minutes: 25) }),
                    (L10n.TestLab.focusEnterOvertime, { harness.focusEnterOvertime() }),
                    (L10n.TestLab.focusEnterCompleted, { harness.focusEnterCompleted() }),
                    (L10n.TestLab.focusAdvance1m, { harness.focusAdvance(byMinutes: 1) }),
                    (L10n.TestLab.focusRemain1m, { harness.focusJumpToRemaining(seconds: 60) }),
                    (L10n.TestLab.focusJumpEnd, { harness.focusJumpToEnd() }),
                    (L10n.TestLab.focusJumpOvertime, { harness.focusJumpIntoOvertime() })
                ])
            }
        }
    }

    private var focusPhaseLine: String {
        let snap = focus.snapshot
        return "\(snap.phase.rawValue) · remain \(snap.remainingSeconds)s · elapsed \(snap.elapsedSeconds)s"
    }

    // MARK: Meeting

    private var meetingCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.meetingTitle, symbol: "calendar")
                Text(L10n.TestLab.meetingSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                if meeting.authStatus != .authorized {
                    SettingsPermissionCard(
                        status: meeting.authStatus == .notDetermined ? .request : .openSettings,
                        symbol: "calendar",
                        title: L10n.TestLab.meetingNeedAuth,
                        subtitle: L10n.TestLab.meetingAuthHint,
                        action: {
                            Task { _ = await MeetingCalendarService.shared.requestAccess() }
                        }
                    )
                }
                Picker(L10n.TestLab.meetingPlatform, selection: $harness.selectedMeetingPlatform) {
                    ForEach(MeetingPlatform.supportedForJoin) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                .pickerStyle(.menu)
                Picker(L10n.TestLab.meetingUrgency, selection: $harness.selectedMeetingUrgency) {
                    ForEach(MeetingLeadUrgency.allCases) { urgency in
                        Text("\(urgency.stageTitle) · \(urgencyLabel(urgency))").tag(urgency)
                    }
                }
                .pickerStyle(.menu)
                HStack(spacing: 8) {
                    labButton(L10n.TestLab.meetingCreate) { harness.createSelectedMeeting() }
                    labButton(L10n.TestLab.meetingCleanup, role: .destructive) { harness.cleanupMeetings() }
                }
            }
        }
    }

    private func urgencyLabel(_ urgency: MeetingLeadUrgency) -> String {
        let sec = Int(IslandTestLabMeetingSeeder.secondsUntilStart(for: urgency))
        return "+\(sec / 60)m\(sec % 60 == 0 ? "" : "\(sec % 60)s")"
    }

    // MARK: Process

    private var processCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.processTitle, symbol: "terminal")
                Text(L10n.TestLab.processSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                if let pid = harness.lastLaunchedPID {
                    Text(L10n.TestLab.processLastPID(Int(pid)))
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
                flowWrap([
                    (L10n.TestLab.processLaunchSleep, { harness.launchSleepAndWatch(seconds: 12) }),
                    (L10n.TestLab.processLaunchDocker, { harness.launchDockerAndWatch(seconds: 15) }),
                    (L10n.TestLab.processTipOK, { harness.presentProcessEndedTip(success: true) }),
                    (L10n.TestLab.processTipFail, { harness.presentProcessEndedTip(success: false) })
                ])
            }
        }
    }

    // MARK: Peripheral

    private var peripheralCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.peripheralTitle, symbol: "battery.100")
                Text(L10n.TestLab.peripheralSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                flowWrap([
                    (L10n.TestLab.peripheralInjectMouse, {
                        harness.injectPeripheralDevice(kind: .mouse, percent: 12, isLow: true)
                    }),
                    (L10n.TestLab.peripheralInjectHeadphones, {
                        harness.injectPeripheralDevice(kind: .headphones, percent: 86, isLow: false)
                    }),
                    (L10n.TestLab.peripheralInjectKeyboard, {
                        harness.injectPeripheralDevice(kind: .keyboard, percent: 100, isLow: false)
                    }),
                    (L10n.TestLab.peripheralClear, { harness.clearPeripheralInjects() }),
                    (L10n.TestLab.peripheralTipLow, { harness.presentPeripheralTip(style: .low) }),
                    (L10n.TestLab.peripheralTipFull, { harness.presentPeripheralTip(style: .full) }),
                    (L10n.TestLab.peripheralTipConnect, { harness.presentPeripheralTip(style: .connect) })
                ])
            }
        }
    }

    // MARK: Control deck

    private var controlDeckCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.deckTitle, symbol: "square.grid.2x2")
                Text(L10n.TestLab.deckSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                flowWrap(
                    ControlDeckSettings.Pane.allCases.map { pane in
                        (pane.title, { harness.openControlDeck(pane: pane) })
                    }
                )
            }
        }
    }

    // MARK: Combos

    private var comboCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                sectionTitle(L10n.TestLab.comboTitle, symbol: "rectangle.split.2x1")
                Text(L10n.TestLab.comboSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                flowWrap([
                    (L10n.TestLab.comboMediaFocus, { harness.comboMediaPlusFocus() }),
                    (L10n.TestLab.comboMediaFocusC, { harness.comboMediaFocusPlusC() })
                ])
            }
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label {
            Text(title)
                .font(SettingsChrome.Font.sectionTitle)
                .foregroundStyle(SettingsChrome.onSurface)
        } icon: {
            Image(systemName: symbol)
                .font(SettingsChrome.Font.iconTile)
                .foregroundStyle(SettingsChrome.primary)
        }
    }

    private func labButton(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func flowWrap(_ items: [(String, () -> Void)]) -> some View {
        // LazyVGrid 比自写 Flow 稳；测试台按钮密集时可换行。
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                labButton(item.0, action: item.1)
            }
        }
    }
}
#endif
