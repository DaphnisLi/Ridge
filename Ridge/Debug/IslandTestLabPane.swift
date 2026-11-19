#if DEBUG
import SwiftUI

/// 设置侧栏「岛测试台」：仅 DEBUG 编译；Release 无入口。
struct IslandTestLabPane: View {
    @ObservedObject private var labSettings = IslandTestLabSettings.shared
    @ObservedObject private var harness = IslandTestHarness.shared
    @ObservedObject private var focus = FocusTimerSession.shared
    @ObservedObject private var meeting = MeetingCalendarService.shared

    private var cardPad: CGFloat { SettingsChrome.Spacing.cardPadding }
    private var cardGap: CGFloat { SettingsChrome.Spacing.cardInner }

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
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SettingsChrome.pageBackground)
        .onAppear {
            AppLog.info("TestLab", "测试台页已显示")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.TestLab.pageTitle)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.TestLab.pageSubtitle)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private var statusBanner: some View {
        SettingsCard {
            Text(harness.statusMessage)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(cardPad)
        }
    }

    // MARK: Tip duration

    private var tipDurationCard: some View {
        labCard(title: L10n.TestLab.tipDurationTitle, symbol: "timer", subtitle: L10n.TestLab.tipDurationSubtitle) {
            SettingsSwitchRow(
                title: L10n.TestLab.tipOverrideSwitch,
                subtitle: L10n.TestLab.tipOverrideHint,
                isOn: $labSettings.tipOverrideEnabled
            )
            .padding(.horizontal, -cardPad)

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

            labButton(L10n.TestLab.tipReset) {
                labSettings.resetTipDuration()
            }
        }
    }

    // MARK: Media

    private var mediaCard: some View {
        labCard(title: L10n.TestLab.mediaTitle, symbol: "music.note", subtitle: L10n.TestLab.mediaSubtitle) {
            buttonRow([
                (L10n.TestLab.mediaFakeOn, { harness.setFakeMediaPlaying(true) }),
                (L10n.TestLab.mediaFakeOff, { harness.setFakeMediaPlaying(false) })
            ])
        }
    }

    // MARK: Focus

    private var focusCard: some View {
        labCard(title: L10n.TestLab.focusTitle, symbol: "timer.circle", subtitle: L10n.TestLab.focusSubtitle) {
            Text(focusPhaseLine)
                .font(SettingsChrome.Font.monoCaption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
                )

            buttonGrid([
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

    private var focusPhaseLine: String {
        let snap = focus.snapshot
        return "\(snap.phase.rawValue) · remain \(snap.remainingSeconds)s · elapsed \(snap.elapsedSeconds)s"
    }

    // MARK: Meeting

    private var meetingCard: some View {
        labCard(title: L10n.TestLab.meetingTitle, symbol: "calendar", subtitle: L10n.TestLab.meetingSubtitle) {
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

            VStack(alignment: .leading, spacing: 10) {
                labeledPicker(L10n.TestLab.meetingPlatform) {
                    Picker("", selection: $harness.selectedMeetingPlatform) {
                        ForEach(MeetingPlatform.supportedForJoin) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                labeledPicker(L10n.TestLab.meetingUrgency) {
                    Picker("", selection: $harness.selectedMeetingUrgency) {
                        ForEach(MeetingLeadUrgency.allCases) { urgency in
                            Text("\(urgency.stageTitle) · \(urgencyLabel(urgency))").tag(urgency)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            buttonRow([
                (L10n.TestLab.meetingCreate, { harness.createSelectedMeeting() }),
                (L10n.TestLab.meetingCleanup, { harness.cleanupMeetings() })
            ], destructiveSecond: true)
        }
    }

    private func urgencyLabel(_ urgency: MeetingLeadUrgency) -> String {
        let sec = Int(IslandTestLabMeetingSeeder.secondsUntilStart(for: urgency))
        return "+\(sec / 60)m\(sec % 60 == 0 ? "" : "\(sec % 60)s")"
    }

    // MARK: Process

    private var processCard: some View {
        labCard(title: L10n.TestLab.processTitle, symbol: "terminal", subtitle: L10n.TestLab.processSubtitle) {
            if let pid = harness.lastLaunchedPID {
                Text(L10n.TestLab.processLastPID(Int(pid)))
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            buttonGrid([
                (L10n.TestLab.processLaunchSleep, { harness.launchSleepAndWatch(seconds: 12) }),
                (L10n.TestLab.processLaunchDocker, { harness.launchDockerAndWatch(seconds: 15) }),
                (L10n.TestLab.processTipOK, { harness.presentProcessEndedTip(success: true) }),
                (L10n.TestLab.processTipFail, { harness.presentProcessEndedTip(success: false) })
            ])
        }
    }

    // MARK: Peripheral

    private var peripheralCard: some View {
        labCard(title: L10n.TestLab.peripheralTitle, symbol: "battery.100", subtitle: L10n.TestLab.peripheralSubtitle) {
            buttonGrid([
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

    // MARK: Control deck

    private var controlDeckCard: some View {
        labCard(title: L10n.TestLab.deckTitle, symbol: "square.grid.2x2", subtitle: L10n.TestLab.deckSubtitle) {
            buttonGrid(
                ControlDeckSettings.Pane.allCases.map { pane in
                    (pane.title, { harness.openControlDeck(pane: pane) })
                }
            )
        }
    }

    // MARK: Combos

    private var comboCard: some View {
        labCard(title: L10n.TestLab.comboTitle, symbol: "rectangle.split.2x1", subtitle: L10n.TestLab.comboSubtitle) {
            buttonGrid([
                (L10n.TestLab.comboMediaFocus, { harness.comboMediaPlusFocus() }),
                (L10n.TestLab.comboMediaFocusC, { harness.comboMediaFocusPlusC() })
            ])
        }
    }

    // MARK: Card chrome

    @ViewBuilder
    private func labCard<Content: View>(
        title: String,
        symbol: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: cardGap) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SettingsChrome.primary.opacity(0.12))
                        Image(systemName: symbol)
                            .font(SettingsChrome.Font.iconInline)
                            .foregroundStyle(SettingsChrome.primary)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(SettingsChrome.Font.sectionTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(subtitle)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content()
            }
            .padding(cardPad)
        }
    }

    private func labeledPicker<Content: View>(
        _ title: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(SettingsChrome.Font.label)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .frame(width: 48, alignment: .leading)
            picker()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private func labButton(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: action)
            .buttonStyle(.bordered)
            .controlSize(.regular)
    }

    private func buttonRow(
        _ items: [(String, () -> Void)],
        destructiveSecond: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                labButton(
                    item.0,
                    role: destructiveSecond && index == 1 ? .destructive : nil,
                    action: item.1
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func buttonGrid(_ items: [(String, () -> Void)]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 10, alignment: .leading)
            ],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                labButton(item.0, action: item.1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif
