import SwiftUI

/// 嵌入「番茄倒计时」配置页：四态 Tab 舞台 + 今日倒计时/正计时双栏 + 预设。
struct FocusTimerWidgetConfigSection: View {
    @ObservedObject private var settings = FocusTimerSettings.shared
    @State private var previewTab: FocusTimerPreviewTab = .standby
    /// 看板补填：正在编辑的记录 id。
    @State private var editingRecordID: UUID?
    @State private var titleDraft: String = ""

    /// 今日全部真实记录。
    private var boardRecords: [FocusTimerRecord] { settings.todayRecords }

    /// 倒计时栏：预设 / 自定义 / 加时（非正计时）。
    private var countdownRecords: [FocusTimerRecord] {
        boardRecords.filter { $0.kind != .countUp }
    }

    /// 正计时栏。
    private var countUpRecords: [FocusTimerRecord] {
        boardRecords.filter { $0.kind == .countUp }
    }

    private var boardFocusMinutes: Int {
        boardRecords.reduce(0) { $0 + $1.totalMinutes }
    }

    private var boardOvertimeMinutes: Int { settings.todayOvertimeMinutes }

    /// 正计时栏强调色（稿面绿点 / 角标）。
    private var countUpTint: Color { Color(red: 0.20, green: 0.70, blue: 0.40) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    islandStageCard
                    // 概览 + 预设并排，再接今日倒计时 | 正计时双栏。
                    overviewAndPresetsRow
                    historyBoard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreDefaults()
                AppLog.info("FocusTimer", "用户恢复默认设置")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            AppLog.debug("FocusTimer", "设置配置区已显示", ["today": boardRecords.count])
        }
    }

    // MARK: - 四态舞台（统一 SettingsIslandStage）

    private var islandStageCard: some View {
        SettingsIslandStage(
            options: FocusTimerPreviewTab.allCases.map(stageOption),
            selection: Binding(
                get: { previewTab.rawValue },
                set: { previewTab = FocusTimerPreviewTab(rawValue: $0) ?? .standby }
            )
        ) { option in
            let tab = FocusTimerPreviewTab(rawValue: option.id) ?? .standby
            // 详情：待命胶囊 / 选时·终局展开；库卡才用会议同款 290 chrome。
            FocusTimerIslandCardView.previewSample(phase: tab.phase, compact: tab.isCompact)
                .padding(
                    .horizontal,
                    tab.isCompact ? 8 : IslandChrome.contentHorizontal
                )
                .padding(.top, previewTopPadding(tab))
                .padding(.bottom, previewBottomPadding(tab))
        }
    }

    private func previewTopPadding(_ tab: FocusTimerPreviewTab) -> CGFloat {
        // 待命胶囊：与真岛一致略加大顶距。
        if tab.isCompact {
            return 6 + FocusTimerCompactMetrics.standbyTopNudge
        }
        // 终局翼 tip：顶 0（贴刘海），与真岛 notchWingTip 一致。
        if tab == .completed { return FocusTimerContentSize.completedPreviewTopInset }
        return IslandChrome.contentBottom
    }

    private func previewBottomPadding(_ tab: FocusTimerPreviewTab) -> CGFloat {
        if tab.isCompact { return 6 }
        if tab == .completed { return FocusTimerContentSize.completedBottomInset }
        return IslandChrome.contentBottom
    }

    private func stageOption(_ tab: FocusTimerPreviewTab) -> SettingsIslandStageOption {
        SettingsIslandStageOption(
            id: tab.rawValue,
            title: tabTitle(tab),
            badge: tabBadge(tab),
            symbol: tabIcon(tab),
            tint: tabTint(tab),
            // 详情宽与媒体统一；库卡另走 290。
            maxIslandWidth: tab.isCompact
                ? SettingsIslandPreviewWidth.standby
                : SettingsIslandPreviewWidth.expanded,
            hugsContent: tab == .completed,
            bottomRadius: tab.isCompact || tab == .completed ? 20 : 24,
            minStageHeight: tab.isCompact ? 120 : (tab == .completed ? 100 : 148),
            compactShell: tab.isCompact
        )
    }

    private func tabTitle(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return L10n.FocusTimer.phaseStandby
        case .picking: return L10n.FocusTimer.phasePicking
        case .overtime: return L10n.FocusTimer.phaseOvertime
        case .countUp: return L10n.FocusTimer.phaseCountUp
        case .completed: return L10n.FocusTimer.phaseCompleted
        }
    }

    private func tabBadge(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return "23:42"
        case .picking: return L10n.FocusTimer.tabBadgeCustom
        case .overtime: return "+10m"
        case .countUp: return "1:27:32"
        case .completed: return "25m"
        }
    }

    private func tabIcon(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return "hourglass"
        case .picking: return "slider.horizontal.3"
        case .overtime: return "alarm.fill"
        case .countUp: return "timer"
        case .completed: return "checkmark.seal.fill"
        }
    }

    private func tabTint(_ tab: FocusTimerPreviewTab) -> Color {
        switch tab {
        case .standby: return SettingsChrome.primary
        case .picking: return Color(red: 0.30, green: 0.29, blue: 0.79)
        case .overtime: return Color(red: 0.85, green: 0.47, blue: 0.02)
        case .countUp: return Color(red: 0.20, green: 0.70, blue: 0.40)
        case .completed: return SettingsChrome.secondary
        }
    }

    // MARK: - 概览 + 预设（并排）

    private var overviewAndPresetsRow: some View {
        // 概览 2/5、预设 3/5；自定义 Layout，避免 ScrollView + containerRelativeFrame 卡死。
        FocusTimerRatioSplit(
            leftFraction: 2.0 / 5.0,
            spacing: SettingsChrome.Spacing.stack
        ) {
            overviewCard
            presetsCard
        }
    }

    /// Variant B：左侧大工时 + 右侧两行条带；与预设卡同高。
    private var overviewCard: some View {
        let extendAccent = Color(red: 0.96, green: 0.62, blue: 0.04)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(SettingsChrome.primary.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "chart.bar.fill")
                        .font(SettingsChrome.Font.iconInline)
                        .foregroundStyle(SettingsChrome.primary)
                }
                Text(L10n.FocusTimer.overviewTitle)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer(minLength: 4)
                Text(L10n.FocusTimer.overviewTodayStats)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant.opacity(0.7))
            }

            FocusTimerRatioSplit(leftFraction: 7.0 / 12.0, spacing: 8) {
                overviewFocusHero
                VStack(spacing: 8) {
                    overviewSideStrip(
                        title: L10n.FocusTimer.overviewTodayTotal,
                        symbol: "clock.arrow.circlepath",
                        tint: SettingsChrome.primary,
                        valueText: "\(boardRecords.count)",
                        unit: L10n.FocusTimer.overviewTimesUnit
                    )
                    overviewSideStrip(
                        title: L10n.FocusTimer.overviewOvertimeSprint,
                        symbol: "timelapse",
                        tint: extendAccent,
                        valueText: "\(boardOvertimeMinutes)",
                        unit: L10n.Common.minuteUnit
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 4) {
                Text(L10n.FocusTimer.overviewFooterHint)
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 4)
                Text(L10n.FocusTimer.overviewFocusMode)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                        .strokeBorder(SettingsChrome.outlineVariant.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }

    private var overviewFocusHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(SettingsChrome.secondary.opacity(0.15))
                        .frame(width: 20, height: 20)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SettingsChrome.secondary)
                }
                Text(L10n.FocusTimer.overviewFocusHours)
                    .font(SettingsChrome.Font.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Circle()
                    .fill(SettingsChrome.secondary)
                    .frame(width: 8, height: 8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(boardFocusMinutes)")
                    .font(SettingsChrome.Font.heroMetric)
                    .monospacedDigit()
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L10n.FocusTimer.overviewMinutesUnit)
                    .font(SettingsChrome.Font.label)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private func overviewSideStrip(
        title: String,
        symbol: String,
        tint: Color,
        valueText: String,
        unit: String
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 20, height: 20)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(SettingsChrome.Font.footnote)
                .fontWeight(.medium)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(valueText)
                    .font(SettingsChrome.Font.monoEmphasis)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(unit)
                    .font(SettingsChrome.Font.badgeTiny)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    // MARK: - 今日看板（左倒计时 · 右正计时）

    private var historyBoard: some View {
        HStack(alignment: .top, spacing: SettingsChrome.Spacing.stack) {
            historyColumn(
                title: L10n.FocusTimer.historyCountdownTitle,
                badge: L10n.FocusTimer.historyCountdownBadge(countdownRecords.count),
                tint: SettingsChrome.primary,
                badgeForeground: SettingsChrome.onSurfaceVariant,
                badgeBackground: SettingsChrome.surfaceContainer,
                records: countdownRecords,
                emptyTitle: L10n.FocusTimer.historyEmptyCountdownTitle,
                emptyHint: L10n.FocusTimer.historyEmptyCountdownHint,
                emptySymbol: "stopwatch",
                isCountUp: false
            )
            historyColumn(
                title: L10n.FocusTimer.historyCountUpTitle,
                badge: L10n.FocusTimer.historyCountUpBadge(countUpRecords.count),
                tint: countUpTint,
                badgeForeground: Color(red: 0.12, green: 0.42, blue: 0.28),
                badgeBackground: Color(red: 0.86, green: 0.96, blue: 0.90),
                records: countUpRecords,
                emptyTitle: L10n.FocusTimer.historyEmptyCountUpTitle,
                emptyHint: L10n.FocusTimer.historyEmptyCountUpHint,
                emptySymbol: "timer",
                isCountUp: true
            )
        }
    }

    private func historyColumn(
        title: String,
        badge: String,
        tint: Color,
        badgeForeground: Color,
        badgeBackground: Color,
        records: [FocusTimerRecord],
        emptyTitle: String,
        emptyHint: String,
        emptySymbol: String,
        isCountUp: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle().fill(tint).frame(width: 10, height: 10)
                Text(title)
                    .font(SettingsChrome.Font.sectionTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer(minLength: 4)
                Text(badge)
                    .font(SettingsChrome.Font.monoCaption)
                    .fontWeight(isCountUp ? .semibold : .regular)
                    .foregroundStyle(badgeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeBackground))
            }

            SettingsHairline.flush

            if records.isEmpty {
                historyEmptyState(
                    tint: tint,
                    symbol: emptySymbol,
                    title: emptyTitle,
                    hint: emptyHint
                )
            } else {
                ForEach(Array(records.prefix(8))) { record in
                    historyRow(record, tint: tint, isCountUp: isCountUp)
                }
            }
        }
        .padding(SettingsChrome.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }

    private func historyEmptyState(
        tint: Color,
        symbol: String,
        title: String,
        hint: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
            Text(title)
                .font(SettingsChrome.Font.cardTitle)
                .foregroundStyle(SettingsChrome.onSurface)
                .multilineTextAlignment(.center)
            Text(hint)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func historyRow(
        _ record: FocusTimerRecord,
        tint: Color,
        isCountUp: Bool
    ) -> some View {
        if record.isUntitled || editingRecordID == record.id {
            FocusTimerTitleBackfillCard(
                record: record,
                barTint: tint,
                style: isCountUp ? .countUp : .countdown,
                suggestedTitles: suggestedTitles(excluding: record.id),
                isEditing: editingRecordID == record.id,
                draft: $titleDraft,
                onBeginEdit: {
                    editingRecordID = record.id
                    titleDraft = ""
                    AppLog.debug("FocusTimer", "看板进入补填", [
                        "id": String(record.id.uuidString.prefix(8)),
                        "countUp": isCountUp
                    ])
                },
                onSave: { title in
                    saveBoardTitle(recordID: record.id, title: title)
                    editingRecordID = nil
                    titleDraft = ""
                },
                onCancel: {
                    editingRecordID = nil
                    titleDraft = ""
                }
            )
        } else if isCountUp {
            namedCountUpRow(record)
        } else {
            namedHistoryRow(record)
        }
    }

    private func suggestedTitles(excluding id: UUID) -> [String] {
        settings.frequentTitles(limit: 5, excluding: id)
    }

    private func saveBoardTitle(recordID: UUID, title: String) {
        settings.updateRecordTitle(id: recordID, title: title)
    }

    private func namedHistoryRow(_ record: FocusTimerRecord) -> some View {
        // 左上实际时长 · 中标题 · 右上加时（无加时不展示）；二行时段+状态；进度条（无底行达成%/加时）。
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(FocusTimerFormatting.clock(record.totalMinutes * 60))
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(
                        record.endedEarly ? SettingsChrome.error : SettingsChrome.onSurface
                    )
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                Text(record.title)
                    .font(SettingsChrome.Font.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if record.overtimeMinutes > 0 {
                    Text(L10n.FocusTimer.overtimePlusMinutes(record.overtimeMinutes))
                        .font(SettingsChrome.Font.monoCaption)
                        .fontWeight(.bold)
                        .foregroundStyle(SettingsChrome.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            HStack(spacing: 6) {
                Text(timeRange(record))
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 4)
                statusChip(endedEarly: record.endedEarly)
            }

            recordProgressBar(record: record)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    /// 正计时具名行：左「秒表」+ 标题 / 时段；右大字实际时长。
    private func namedCountUpRow(_ record: FocusTimerRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    countUpStopwatchBadge
                    Text(record.title)
                        .font(SettingsChrome.Font.rowTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(1)
                }
                Text(timeRange(record))
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Text(FocusTimerFormatting.countUpClock(Self.wallSeconds(record)))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(SettingsChrome.onSurface)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private var countUpStopwatchBadge: some View {
        Text(L10n.FocusTimer.historyCountUpStopwatchBadge)
            .font(SettingsChrome.Font.monoCaption)
            .fontWeight(.semibold)
            .foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.28))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(red: 0.86, green: 0.96, blue: 0.90))
            )
    }

    /// 正计时展示用墙钟秒数（保留时分秒精度）。
    private static func wallSeconds(_ record: FocusTimerRecord) -> Int {
        max(0, Int(record.endedAt.timeIntervalSince(record.startedAt)))
    }

    private func statusChip(endedEarly: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: endedEarly ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(
                endedEarly
                    ? L10n.FocusTimer.endedEarlyStatus
                    : L10n.FocusTimer.finishedOnTimeStatus
            )
            .font(SettingsChrome.Font.footnote)
            .fontWeight(.medium)
        }
        .foregroundStyle(endedEarly ? SettingsChrome.error : SettingsChrome.secondary)
    }

    /// 准时：满条绿；提前：红条按实际/计划比例；顺延准时：蓝+琥珀渐变分段。
    private func recordProgressBar(record: FocusTimerRecord) -> some View {
        let barHeight: CGFloat = record.overtimeMinutes > 0 && !record.endedEarly ? 10 : 6
        return Group {
            if record.endedEarly {
                let planned = max(record.plannedMinutes, 1)
                let ratio = min(1, CGFloat(record.totalMinutes) / CGFloat(planned))
                GeometryReader { geo in
                    Capsule()
                        .fill(SettingsChrome.surfaceContainer)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(SettingsChrome.error)
                                .frame(width: max(4, geo.size.width * ratio))
                        }
                }
                .frame(height: barHeight)
            } else if record.overtimeMinutes > 0 {
                dualBar(record: record)
            } else {
                GeometryReader { geo in
                    Capsule()
                        .fill(SettingsChrome.surfaceContainer)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(SettingsChrome.secondary)
                                .frame(width: geo.size.width)
                        }
                }
                .frame(height: barHeight)
            }
        }
    }

    private func dualBar(record: FocusTimerRecord) -> some View {
        // 按「计划 + 顺延」分段；右侧琥珀→绿渐变表示加时。
        let schedule = max(record.plannedMinutes + record.overtimeMinutes, 1)
        let base = CGFloat(record.plannedMinutes) / CGFloat(schedule)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 999,
                    bottomLeadingRadius: 999,
                    bottomTrailingRadius: 2,
                    topTrailingRadius: 2,
                    style: .continuous
                )
                .fill(SettingsChrome.primary)
                .frame(width: max(8, geo.size.width * base - 1))
                UnevenRoundedRectangle(
                    topLeadingRadius: 2,
                    bottomLeadingRadius: 2,
                    bottomTrailingRadius: 999,
                    topTrailingRadius: 999,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.62, blue: 0.04),
                            Color(red: 1.0, green: 0.80, blue: 0.35),
                            SettingsChrome.secondary
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(8, geo.size.width * (1 - base) - 1))
            }
        }
        .frame(height: 10)
    }

    private func timeRange(_ record: FocusTimerRecord) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return "\(f.string(from: record.startedAt)) - \(f.string(from: record.endedAt))"
    }

    // MARK: - 预设档位

    private var presetsCard: some View {
        let extendAccent = Color(red: 0.96, green: 0.62, blue: 0.04)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(SettingsChrome.primary.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "stopwatch")
                        .font(SettingsChrome.Font.iconInline)
                        .foregroundStyle(SettingsChrome.primary)
                }
                Text(L10n.FocusTimer.presetsTitle)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            HStack(spacing: 8) {
                ForEach(settings.presets) { preset in
                    presetMinuteSlot(preset)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "alarm.fill")
                    .font(SettingsChrome.Font.iconInline)
                    .foregroundStyle(extendAccent)
                Text(L10n.FocusTimer.extendStepShort)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach(FocusTimerSettings.Defaults.extendStepOptions, id: \.self) { minutes in
                        extendStepChip(minutes, accent: extendAccent)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
                )
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                        .strokeBorder(SettingsChrome.outlineVariant.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }

    private func presetMinuteSlot(_ preset: FocusTimerPreset) -> some View {
        let step = presetAdjustStep(for: preset)
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(preset.minutes)")
                    .font(SettingsChrome.Font.metricEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Common.minuteUnit)
                    .font(SettingsChrome.Font.badgeTiny)
                    .fontWeight(.medium)
                    .foregroundStyle(SettingsChrome.outline)
            }

            HStack(spacing: 4) {
                presetAdjustButton(L10n.FocusTimer.presetAdjustMinus(step)) {
                    settings.bumpPresetMinutes(id: preset.id, delta: -step)
                }
                presetAdjustButton(L10n.FocusTimer.presetAdjustPlus(step)) {
                    settings.bumpPresetMinutes(id: preset.id, delta: step)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private func presetAdjustStep(for preset: FocusTimerPreset) -> Int {
        preset.adjustStepMinutes
    }

    private func presetAdjustButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SettingsChrome.Font.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(SettingsChrome.onSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.cardBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private func extendStepChip(_ minutes: Int, accent: Color) -> some View {
        let selected = settings.extendStepMinutes == minutes
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button {
            settings.extendStepMinutes = minutes
            AppLog.info("FocusTimer", "切换顺延步长", ["minutes": minutes])
        } label: {
            Text(L10n.FocusTimer.extendStepChip(minutes))
                .font(SettingsChrome.Font.monoCaption)
                .fontWeight(.semibold)
                .foregroundStyle(selected ? accent : SettingsChrome.onSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    shape
                        .fill(selected ? SettingsChrome.cardBackground : Color.clear)
                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 1.5, y: 0.5)
                )
                // plain Button 默认只点文字；整块芯片都要可点。
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// 横向按比例拆两列；不依赖 GeometryReader / containerRelativeFrame，ScrollView 内安全。
private struct FocusTimerRatioSplit: Layout {
    var leftFraction: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2, let width = proposal.width, width.isFinite, width > 0 else {
            let heights = subviews.map { $0.sizeThatFits(proposal).height }
            return CGSize(width: proposal.width ?? 0, height: heights.max() ?? 0)
        }
        let leftW = max(0, (width - spacing) * leftFraction)
        let rightW = max(0, (width - spacing) * (1 - leftFraction))
        let leftH = subviews[0].sizeThatFits(.init(width: leftW, height: proposal.height)).height
        let rightH = subviews[1].sizeThatFits(.init(width: rightW, height: proposal.height)).height
        return CGSize(width: width, height: max(leftH, rightH))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let leftW = max(0, (bounds.width - spacing) * leftFraction)
        let rightW = max(0, (bounds.width - spacing) * (1 - leftFraction))
        // 两列同高铺满，让左右卡片 / 工时与右侧条带对齐。
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: .init(width: leftW, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leftW + spacing, y: bounds.minY),
            proposal: .init(width: rightW, height: bounds.height)
        )
    }
}
