#if DEBUG
import SwiftUI

/// 岛测试台下方「样式图鉴」：用与设置预览相同的假数据组件，把当前真样式全状态铺开。
/// 点击样张会经 `IslandTestHarness` 投到真岛。仅 DEBUG；Release 无此类型。
struct IslandStyleGallerySection: View {
    private var harness: IslandTestHarness { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
            galleryHeader

            // 按组件分卡，与上方测试工具分区一致。
            galleryGroup(title: L10n.TestLab.galleryMeeting) { tipMeetingRows }
            galleryGroup(title: L10n.TestLab.galleryAI) { tipAIRows }
            galleryGroup(title: L10n.TestLab.galleryMove) { tipMoveRows }
            galleryGroup(title: L10n.TestLab.galleryRAM) { tipRAMRows }
            galleryGroup(title: L10n.TestLab.galleryProcess) { tipProcessRows }
            galleryGroup(title: L10n.TestLab.galleryPeripheral) { tipPeripheralRows }
            galleryGroup(title: L10n.TestLab.galleryMacBattery) { tipMacBatteryRows }
            galleryGroup(title: L10n.TestLab.gallerySystemFocus) { tipSystemFocusRows }
            galleryGroup(title: L10n.TestLab.galleryCapture) { tipCaptureRows }
            galleryGroup(title: L10n.TestLab.galleryMedia) { liveMediaRows }
            galleryGroup(title: L10n.TestLab.galleryFocus) { liveFocusRows }
            galleryGroup(title: L10n.TestLab.galleryWorldStocks) { liveWorldAndStocks }
            galleryGroup(title: L10n.TestLab.galleryDeck) { deckRows }
        }
        .onAppear {
            AppLog.info("TestLab", "样式图鉴已显示（按组件）")
        }
    }

    private var galleryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.primary.opacity(0.12))
                    Image(systemName: "rectangle.grid.3x2")
                        .font(SettingsChrome.Font.iconInline)
                        .foregroundStyle(SettingsChrome.primary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.TestLab.galleryTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.TestLab.gallerySubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.TestLab.galleryTapHint)
                        .font(SettingsChrome.Font.footnote)
                        .foregroundStyle(SettingsChrome.primary)
                }
            }
        }
    }

    // MARK: - Tips（每态整岛 + 半岛并排；半岛只画自身半翼）

    private var tipMeetingRows: some View {
        // 两列：整岛 | 半岛，按紧迫度成对排布；点击均投同一紧迫度样张。
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            ForEach(MeetingLeadUrgency.allCases) { urgency in
                tipCell(
                    label: pairedLabel(urgency.stageTitle, half: false),
                    onTap: { harness.presentMeetingTip(urgency: urgency) }
                ) {
                    MeetingIslandCardView.previewSample(urgency: urgency, compact: true)
                        .padding(.horizontal, IslandChrome.contentHorizontal)
                        .padding(.bottom, IslandChrome.compactTipBottom)
                }
                flushCell(
                    label: pairedLabel(urgency.stageTitle, half: true),
                    onTap: { harness.presentMeetingTip(urgency: urgency) }
                ) {
                    MeetingIslandCardView.previewSample(
                        urgency: urgency,
                        compact: true,
                        flushSide: .leading
                    )
                }
            }
        }
    }

    private var tipPeripheralRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            tipCell(
                label: pairedLabel(L10n.PeripheralTip.connectBadge, half: false),
                onTap: { harness.presentPeripheralTip(style: .connect) }
            ) {
                PeripheralBatteryNoticeCard.previewSample(style: .connect, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.PeripheralTip.connectBadge, half: true),
                onTap: { harness.presentPeripheralTip(style: .connect) }
            ) {
                PeripheralBatteryNoticeCard.previewSample(style: .connect, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryPeripheralFull, half: false),
                onTap: { harness.presentPeripheralTip(style: .full) }
            ) {
                PeripheralBatteryNoticeCard.previewSample(style: .full, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryPeripheralFull, half: true),
                onTap: { harness.presentPeripheralTip(style: .full) }
            ) {
                PeripheralBatteryNoticeCard.previewSample(style: .full, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryPeripheralLow, half: false),
                onTap: { harness.presentPeripheralTip(style: .low) }
            ) {
                PeripheralBatteryNoticeCard.previewSample(style: .low, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryPeripheralLow, half: true),
                onTap: { harness.presentPeripheralTip(style: .low) }
            ) {
                PeripheralBatteryNoticeCard.previewSample(style: .low, flushSide: .trailing)
            }
        }
    }

    private var tipMacBatteryRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryCharging, half: false),
                onTap: { harness.presentMacBatteryTip(kind: .charging) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .charging, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryCharging, half: true),
                onTap: { harness.presentMacBatteryTip(kind: .charging) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .charging, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryFull, half: false),
                onTap: { harness.presentMacBatteryTip(kind: .full) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .full, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryFull, half: true),
                onTap: { harness.presentMacBatteryTip(kind: .full) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .full, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryLow, half: false),
                onTap: { harness.presentMacBatteryTip(kind: .low) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .low, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryLow, half: true),
                onTap: { harness.presentMacBatteryTip(kind: .low) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .low, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryUnplug, half: false),
                onTap: { harness.presentMacBatteryTip(kind: .unplugged) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .unplugged, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryMacBatteryUnplug, half: true),
                onTap: { harness.presentMacBatteryTip(kind: .unplugged) }
            ) {
                MacBatteryNoticeCard.previewSample(kind: .unplugged, flushSide: .trailing)
            }
        }
    }

    private var tipSystemFocusRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            tipCell(
                label: pairedLabel(L10n.TestLab.gallerySystemFocusOn, half: false),
                onTap: { harness.presentSystemFocusTip(kind: .on) }
            ) {
                SystemFocusNoticeCard.previewSample(preview: .onOpened, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.gallerySystemFocusOn, half: true),
                onTap: { harness.presentSystemFocusTip(kind: .on) }
            ) {
                SystemFocusNoticeCard.previewSample(preview: .onOpened, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.gallerySystemFocusOff, half: false),
                onTap: { harness.presentSystemFocusTip(kind: .off) }
            ) {
                SystemFocusNoticeCard.previewSample(preview: .off, compact: true)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.gallerySystemFocusOff, half: true),
                onTap: { harness.presentSystemFocusTip(kind: .off) }
            ) {
                SystemFocusNoticeCard.previewSample(preview: .off, flushSide: .trailing)
            }
        }
    }

    private var tipAIRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            ForEach([AIUsageStage.abundant, .warning, .critical], id: \.rawValue) { stage in
                tipCell(
                    label: pairedLabel(stage.label, half: false),
                    onTap: { harness.presentAITip(stage: stage) }
                ) {
                    AIUsageIslandCardView.previewSample(stage: stage, compact: true)
                        .padding(.horizontal, IslandChrome.contentHorizontal)
                        .padding(.bottom, IslandChrome.compactTipBottom)
                }
                flushCell(
                    label: pairedLabel(stage.label, half: true),
                    onTap: { harness.presentAITip(stage: stage) }
                ) {
                    AIUsageIslandCardView.previewSample(stage: stage, flushSide: .trailing)
                }
            }
        }
    }

    private var tipProcessRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryProcessOK, half: false),
                onTap: { harness.presentProcessEndedTip(outcome: .succeeded) }
            ) {
                ProcessEndedNoticeCard.previewSample(outcome: .succeeded)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryProcessOK, half: true),
                onTap: { harness.presentProcessEndedTip(outcome: .succeeded) }
            ) {
                ProcessEndedNoticeCard.previewSample(outcome: .succeeded, flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryProcessFail, half: false),
                onTap: { harness.presentProcessEndedTip(outcome: .failed(code: 1)) }
            ) {
                ProcessEndedNoticeCard.previewSample(outcome: .failed(code: 1))
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryProcessFail, half: true),
                onTap: { harness.presentProcessEndedTip(outcome: .failed(code: 1)) }
            ) {
                ProcessEndedNoticeCard.previewSample(outcome: .failed(code: 1), flushSide: .trailing)
            }
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryProcessSignal, half: false),
                onTap: { harness.presentProcessEndedTip(outcome: .signaled(signal: 15)) }
            ) {
                ProcessEndedNoticeCard.previewSample(outcome: .signaled(signal: 15))
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryProcessSignal, half: true),
                onTap: { harness.presentProcessEndedTip(outcome: .signaled(signal: 15)) }
            ) {
                ProcessEndedNoticeCard.previewSample(outcome: .signaled(signal: 15), flushSide: .trailing)
            }
        }
    }

    private var tipMoveRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryMove, half: false),
                onTap: { harness.presentMoveReminderTip() }
            ) {
                MoveReminderNoticeCard.previewSample(
                    activeMinutes: MoveReminderSettings.shared.activeTriggerMinutes,
                    restMinutes: MoveReminderSettings.shared.suggestedRestMinutes,
                    compact: true
                )
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryMove, half: true),
                onTap: { harness.presentMoveReminderTip() }
            ) {
                MoveReminderNoticeCard.previewSample(
                    activeMinutes: MoveReminderSettings.shared.activeTriggerMinutes,
                    restMinutes: MoveReminderSettings.shared.suggestedRestMinutes,
                    compact: true,
                    flushSide: .trailing
                )
            }
        }
    }

    private var tipRAMRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            tipCell(
                label: pairedLabel(L10n.TestLab.galleryRAM, half: false),
                onTap: { harness.presentRAMTip() }
            ) {
                RAMPressureNoticeCard.previewSample()
            }
            flushCell(
                label: pairedLabel(L10n.TestLab.galleryRAM, half: true),
                onTap: { harness.presentRAMTip() }
            ) {
                RAMPressureNoticeCard.previewSample(flushSide: .trailing)
            }
        }
    }

    private var tipCaptureRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates) {
            tipCell(
                label: L10n.TestLab.galleryColorPick,
                onTap: { harness.presentColorPickTip() }
            ) {
                ColorPickTipIslandView(compact: true)
                    .padding(.horizontal, IslandChrome.contentHorizontal)
                    .padding(.bottom, IslandChrome.compactTipBottom)
            }
            tipCell(
                label: L10n.TestLab.galleryOCR,
                onTap: { harness.presentOCRTip() }
            ) {
                OCRSelectTipIslandView(compact: true)
                    .padding(.horizontal, IslandChrome.contentHorizontal)
                    .padding(.bottom, IslandChrome.compactTipBottom)
            }
            tipCell(
                label: L10n.TestLab.galleryCopied,
                hugs: true,
                outline: .circle,
                stageMinHeight: 72,
                onTap: { harness.presentCopiedTip() }
            ) {
                ClipboardCopiedIslandView(compact: true, animationToken: "gallery.copied")
                    .frame(
                        width: IslandChrome.notchRightOrbDiameter,
                        height: IslandChrome.notchRightOrbDiameter
                    )
            }
        }
    }

    // MARK: - Live

    private var liveMediaRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            panelCell(
                label: L10n.TestLab.galleryMediaStandby,
                maxWidth: SettingsIslandPreviewWidth.standby,
                onTap: { harness.presentMediaStandby() }
            ) {
                MediaCompactStandbyView.previewSample(animatedEqualizer: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            panelCell(
                label: L10n.TestLab.galleryMediaExpanded,
                maxWidth: SettingsIslandPreviewWidth.expanded,
                onTap: { harness.presentMediaExpanded() }
            ) {
                MediaIslandCardView.previewSample(animatedEqualizer: false)
                    .padding(.horizontal, MediaPreviewChrome.expandedHorizontal)
                    .padding(.top, MediaPreviewChrome.expandedTop)
                    .padding(.bottom, MediaPreviewChrome.expandedBottom)
            }
        }
    }

    private var liveFocusRows: some View {
        // 倒计时 / 正计时分开展示，避免混测。
        VStack(alignment: .leading, spacing: 12) {
            galleryRow(title: L10n.TestLab.focusCountdownSection, columns: 2) {
                ForEach(countdownPreviewTabs) { tab in
                    focusPreviewCell(tab)
                }
            }
            galleryRow(title: L10n.TestLab.focusCountUpSection, columns: 2) {
                ForEach(countUpPreviewTabs) { tab in
                    focusPreviewCell(tab)
                }
            }
        }
    }

    private var countdownPreviewTabs: [FocusTimerPreviewTab] {
        [.picking, .standby, .overtime, .completed]
    }

    private var countUpPreviewTabs: [FocusTimerPreviewTab] {
        [.countUp]
    }

    @ViewBuilder
    private func focusPreviewCell(_ tab: FocusTimerPreviewTab) -> some View {
        panelCell(
            label: focusTabTitle(tab),
            maxWidth: tab.isCompact
                ? SettingsIslandPreviewWidth.standby
                : SettingsIslandPreviewWidth.expanded,
            hugs: false,
            onTap: { harness.focusApplyPreviewTab(tab) }
        ) {
            FocusTimerIslandCardView.previewSample(phase: tab.phase, compact: tab.isCompact)
                .padding(
                    .horizontal,
                    tab.isCompact ? 8 : IslandChrome.contentHorizontal
                )
                .padding(
                    .vertical,
                    tab.isCompact ? 6 : IslandChrome.contentBottom
                )
        }
    }

    private var liveWorldAndStocks: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            panelCell(
                label: L10n.TestLab.galleryWorldClock,
                maxWidth: 420,
                hugs: false,
                onTap: {
                    harness.openPanelWidget(
                        id: WorldClockWidget.manifest.id,
                        title: L10n.TestLab.galleryWorldClock
                    )
                }
            ) {
                WorldClockIslandView.previewSample()
                    .padding(.horizontal, IslandChrome.contentHorizontal)
                    .padding(.vertical, 10)
            }
            panelCell(
                label: L10n.TestLab.galleryStocks,
                hugs: true,
                onTap: {
                    harness.openPanelWidget(
                        id: StockWidget.manifest.id,
                        title: L10n.TestLab.galleryStocks
                    )
                }
            ) {
                StockIslandView.previewSample(compact: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Control deck

    private var deckRows: some View {
        galleryRow(title: L10n.TestLab.sectionStates, columns: 2) {
            panelCell(
                label: L10n.TestLab.galleryDeckBattery,
                maxWidth: NotchGeometry.controlDeckPreferredWidth,
                hugs: false,
                contentProvidesOpaqueShell: true,
                onTap: { harness.openControlDeck(pane: .battery) }
            ) {
                WidgetSamplePreview.content(for: "system.controlDeck.battery", compact: false)
            }
            panelCell(
                label: L10n.TestLab.galleryDeckVolume,
                maxWidth: NotchGeometry.controlDeckPreferredWidth,
                hugs: false,
                onTap: { harness.openControlDeck(pane: .volume) }
            ) {
                WidgetSamplePreview.content(for: "system.controlDeck.volume", compact: false)
            }
            panelCell(
                label: L10n.TestLab.galleryDeckProjects,
                maxWidth: NotchGeometry.controlDeckPreferredWidth,
                hugs: false,
                onTap: { harness.openControlDeck(pane: .projects) }
            ) {
                WidgetSamplePreview.content(for: "system.controlDeck.projects", compact: false)
            }
            panelCell(
                label: L10n.TestLab.galleryDeckShelf,
                maxWidth: NotchGeometry.controlDeckPreferredWidth,
                hugs: false,
                onTap: { harness.openControlDeck(pane: .shelf) }
            ) {
                WidgetSamplePreview.content(for: "system.controlDeck.shelf", compact: false)
            }
        }
    }

    // MARK: - Layout helpers

    private func galleryGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
                Text(title)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                content()
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private func galleryRow<Content: View>(
        title: String,
        columns: Int = 3,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SettingsChrome.Font.label)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 10),
                    count: columns
                ),
                alignment: .leading,
                spacing: 10
            ) {
                content()
            }
        }
    }

    private func tipCell<Content: View>(
        label: String,
        hugs: Bool = true,
        outline: IslandOutlineStyle = .panel,
        stageMinHeight: CGFloat = 72,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        galleryCell(label: label, stageMinHeight: stageMinHeight, onTap: onTap) {
            WidgetIslandPreviewShell(
                compact: true,
                outlineStyle: outline,
                hugsContent: hugs
            ) {
                content()
            }
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    /// 半岛样张：卡片自带 flush 黑胶囊，不再套满岛预览壳，也不画并排另一侧。
    private func flushCell<Content: View>(
        label: String,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        galleryCell(label: label, stageMinHeight: 56, onTap: onTap) {
            content()
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func panelCell<Content: View>(
        label: String,
        maxWidth: CGFloat? = nil,
        hugs: Bool = true,
        contentProvidesOpaqueShell: Bool = false,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        galleryCell(label: label, stageMinHeight: 120, onTap: onTap) {
            WidgetIslandPreviewShell(
                compact: false,
                hugsContent: hugs,
                contentProvidesOpaqueShell: contentProvidesOpaqueShell
            ) {
                content()
            }
            .frame(maxWidth: maxWidth)
        }
    }

    @ViewBuilder
    private func galleryCell<Content: View>(
        label: String,
        stageMinHeight: CGFloat,
        onTap: (() -> Void)?,
        @ViewBuilder island: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SettingsChrome.Font.footnote)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .lineLimit(1)
            if let onTap {
                Button(action: onTap) {
                    island()
                        .frame(maxWidth: .infinity, minHeight: stageMinHeight, alignment: .top)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                                .fill(SettingsChrome.surfaceContainer)
                        )
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
                .help(L10n.TestLab.galleryTapHint)
            } else {
                island()
                    .frame(maxWidth: .infinity, minHeight: stageMinHeight, alignment: .top)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusTabTitle(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return L10n.FocusTimer.phaseStandby
        case .picking: return L10n.FocusTimer.phasePicking
        case .overtime: return L10n.FocusTimer.phaseOvertime
        case .countUp: return L10n.FocusTimer.phaseCountUp
        case .completed: return L10n.FocusTimer.phaseCompleted
        }
    }

    /// 同态整岛 / 半岛标签：`从容 · 整岛` / `从容 · 半岛`。
    private func pairedLabel(_ base: String, half: Bool) -> String {
        half ? L10n.TestLab.galleryLabelHalf(base) : L10n.TestLab.galleryLabelFull(base)
    }
}
#endif
