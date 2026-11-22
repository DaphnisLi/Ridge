#if DEBUG
import SwiftUI

/// 设置侧栏「岛测试台」：仅 DEBUG 编译；Release 无入口。
/// 工具按组件分卡：每卡覆盖该组件全部可上岛状态。
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

                meetingCard
                aiCard
                moveCard
                ramCard
                processCard
                peripheralCard
                captureCard
                mediaCard
                focusCard
                worldStocksCard
                controlDeckCard
                comboCard

                IslandStyleGallerySection()

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

    // MARK: Tip duration（全局）

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

            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid(
                MeetingLeadUrgency.allCases.map { urgency in
                    (urgency.stageTitle, { harness.presentMeetingTip(urgency: urgency) })
                }
            )

            sectionLabel(L10n.TestLab.sectionTools)
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

    // MARK: AI

    private var aiCard: some View {
        labCard(title: L10n.TestLab.aiTitle, symbol: "sparkles", subtitle: L10n.TestLab.aiSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid([
                (L10n.AIUsage.stageAbundant, { harness.presentAITip(stage: .abundant) }),
                (L10n.AIUsage.stageWarning, { harness.presentAITip(stage: .warning) }),
                (L10n.AIUsage.stageCritical, { harness.presentAITip(stage: .critical) })
            ])
        }
    }

    // MARK: Move

    private var moveCard: some View {
        labCard(title: L10n.TestLab.moveTitle, symbol: "figure.stand", subtitle: L10n.TestLab.moveSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonRow([
                (L10n.TestLab.tipMove, { harness.presentMoveReminderTip() })
            ])
        }
    }

    // MARK: RAM

    private var ramCard: some View {
        labCard(title: L10n.TestLab.ramTitle, symbol: "memorychip", subtitle: L10n.TestLab.ramSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonRow([
                (L10n.TestLab.tipRAM, { harness.presentRAMTip() })
            ])
        }
    }

    // MARK: Process

    private var processCard: some View {
        labCard(title: L10n.TestLab.processTitle, symbol: "terminal", subtitle: L10n.TestLab.processSubtitle) {
            if let pid = harness.lastLaunchedPID {
                Text(L10n.TestLab.processLastPID(Int(pid)))
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid([
                (L10n.TestLab.galleryProcessOK, {
                    harness.presentProcessEndedTip(outcome: .succeeded)
                }),
                (L10n.TestLab.galleryProcessFail, {
                    harness.presentProcessEndedTip(outcome: .failed(code: 1))
                }),
                (L10n.TestLab.galleryProcessSignal, {
                    harness.presentProcessEndedTip(outcome: .signaled(signal: 15))
                })
            ])
            sectionLabel(L10n.TestLab.sectionTools)
            buttonGrid([
                (L10n.TestLab.processLaunchSleep, { harness.launchSleepAndWatch(seconds: 12) }),
                (L10n.TestLab.processLaunchDocker, { harness.launchDockerAndWatch(seconds: 15) })
            ])
        }
    }

    // MARK: Peripheral

    private var peripheralCard: some View {
        labCard(title: L10n.TestLab.peripheralTitle, symbol: "battery.100", subtitle: L10n.TestLab.peripheralSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid([
                (L10n.PeripheralTip.connectBadge, { harness.presentPeripheralTip(style: .connect) }),
                (L10n.TestLab.galleryPeripheralFull, { harness.presentPeripheralTip(style: .full) }),
                (L10n.TestLab.galleryPeripheralLow, { harness.presentPeripheralTip(style: .low) })
            ])
            sectionLabel(L10n.TestLab.sectionTools)
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
                (L10n.TestLab.peripheralClear, { harness.clearPeripheralInjects() })
            ])
        }
    }

    // MARK: Capture（取色 / OCR / 已复制）

    private var captureCard: some View {
        labCard(title: L10n.TestLab.captureTitle, symbol: "eyedropper", subtitle: L10n.TestLab.captureSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid([
                (L10n.TestLab.galleryCopied, { harness.presentCopiedTip() }),
                (L10n.TestLab.galleryColorPick, { harness.presentColorPickTip() }),
                (L10n.TestLab.galleryOCR, { harness.presentOCRTip() }),
                (L10n.TestLab.tipDismissManual, { harness.dismissManualTips() })
            ])
        }
    }

    // MARK: Media

    private var mediaCard: some View {
        labCard(title: L10n.TestLab.mediaTitle, symbol: "music.note", subtitle: L10n.TestLab.mediaSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid([
                (L10n.TestLab.galleryMediaStandby, { harness.presentMediaStandby() }),
                (L10n.TestLab.galleryMediaExpanded, { harness.presentMediaExpanded() })
            ])
            sectionLabel(L10n.TestLab.sectionTools)
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

            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid(
                FocusTimerPreviewTab.allCases.map { tab in
                    (focusTabTitle(tab), { harness.focusApplyPreviewTab(tab) })
                }
            )

            sectionLabel(L10n.TestLab.sectionTools)
            buttonGrid([
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

    private func focusTabTitle(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return L10n.FocusTimer.phaseStandby
        case .picking: return L10n.FocusTimer.phasePicking
        case .running: return L10n.FocusTimer.phaseRunning
        case .overtime: return L10n.FocusTimer.phaseOvertime
        case .completed: return L10n.FocusTimer.phaseCompleted
        }
    }

    // MARK: World clock / Stocks

    private var worldStocksCard: some View {
        labCard(
            title: L10n.TestLab.worldStocksTitle,
            symbol: "globe",
            subtitle: L10n.TestLab.worldStocksSubtitle
        ) {
            sectionLabel(L10n.TestLab.sectionStates)
            buttonGrid([
                (L10n.TestLab.galleryWorldClock, {
                    harness.openPanelWidget(
                        id: WorldClockWidget.manifest.id,
                        title: L10n.TestLab.galleryWorldClock
                    )
                }),
                (L10n.TestLab.galleryStocks, {
                    harness.openPanelWidget(
                        id: StockWidget.manifest.id,
                        title: L10n.TestLab.galleryStocks
                    )
                })
            ])
        }
    }

    // MARK: Control deck

    private var controlDeckCard: some View {
        labCard(title: L10n.TestLab.deckTitle, symbol: "square.grid.2x2", subtitle: L10n.TestLab.deckSubtitle) {
            sectionLabel(L10n.TestLab.sectionStates)
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(SettingsChrome.Font.label)
            .foregroundStyle(SettingsChrome.onSurfaceVariant)
    }

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
