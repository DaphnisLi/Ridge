import SwiftUI

/// 嵌入「番茄倒计时」配置页：对齐稿面——五态 Tab 舞台 + 三栏看板 + 预设。
struct FocusTimerWidgetConfigSection: View {
    @ObservedObject private var settings = FocusTimerSettings.shared
    @State private var previewTab: FocusTimerPreviewTab = .standby
    /// 看板补填：正在编辑的记录 id。
    @State private var editingRecordID: UUID?
    @State private var titleDraft: String = ""

    /// 仅今日真实记录；无记录时三栏走空态。
    private var boardRecords: [FocusTimerRecord] { settings.todayRecords }

    private var boardPresets: [FocusTimerRecord] {
        boardRecords.filter { $0.kind == .preset && $0.overtimeMinutes == 0 }
    }

    private var boardCustoms: [FocusTimerRecord] {
        boardRecords.filter { $0.kind == .custom && $0.overtimeMinutes == 0 }
    }

    private var boardOvers: [FocusTimerRecord] {
        boardRecords.filter { $0.kind == .overtimeSprint || $0.overtimeMinutes > 0 }
    }

    private var boardFocusMinutes: Int {
        boardRecords.reduce(0) { $0 + $1.totalMinutes }
    }

    private var boardOvertimeMinutes: Int { settings.todayOvertimeMinutes }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    islandStageCard
                    // 稿面：概览 5 + 预设 7 并排，再接三栏记录。
                    overviewAndPresetsRow
                    historyMatrix
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

    // MARK: - 五态舞台（统一 SettingsIslandStage）

    private var islandStageCard: some View {
        SettingsIslandStage(
            options: FocusTimerPreviewTab.allCases.map(stageOption),
            selection: Binding(
                get: { previewTab.rawValue },
                set: { previewTab = FocusTimerPreviewTab(rawValue: $0) ?? .standby }
            )
        ) { option in
            let tab = FocusTimerPreviewTab(rawValue: option.id) ?? .standby
            // 详情：待命/展开保持原先尺寸；库卡才用会议同款 290 chrome。
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
            hugsContent: false,
            bottomRadius: tab.isCompact ? 20 : 24,
            minStageHeight: tab.isCompact ? 120 : 148,
            compactShell: tab.isCompact
        )
    }

    private func tabTitle(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return L10n.FocusTimer.phaseStandby
        case .picking: return L10n.FocusTimer.phasePicking
        case .running: return L10n.FocusTimer.phaseRunning
        case .overtime: return L10n.FocusTimer.phaseOvertime
        case .completed: return L10n.FocusTimer.phaseCompleted
        }
    }

    private func tabBadge(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return "75%"
        case .picking: return L10n.FocusTimer.tabBadgeCustom
        case .running: return "18:42"
        case .overtime: return "+10m"
        case .completed: return L10n.FocusTimer.tabBadgeSummary
        }
    }

    private func tabIcon(_ tab: FocusTimerPreviewTab) -> String {
        switch tab {
        case .standby: return "timer"
        case .picking: return "slider.horizontal.3"
        case .running: return "hourglass"
        case .overtime: return "alarm.fill"
        case .completed: return "checkmark.seal.fill"
        }
    }

    private func tabTint(_ tab: FocusTimerPreviewTab) -> Color {
        switch tab {
        case .standby: return SettingsChrome.primary
        case .picking: return Color(red: 0.30, green: 0.29, blue: 0.79)
        case .running: return SettingsChrome.primaryContainer
        case .overtime: return Color(red: 0.85, green: 0.47, blue: 0.02)
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

    // MARK: - 三栏看板

    private var historyMatrix: some View {
        HStack(alignment: .top, spacing: SettingsChrome.Spacing.stack) {
            historyColumn(
                title: L10n.FocusTimer.colPreset,
                badge: L10n.FocusTimer.colPresetBadge(boardPresets.count),
                tint: SettingsChrome.primary,
                records: boardPresets,
                style: .preset
            )
            historyColumn(
                title: L10n.FocusTimer.colCustom,
                badge: L10n.FocusTimer.colCustomBadge(boardCustoms.count),
                tint: Color(red: 0.30, green: 0.29, blue: 0.79),
                records: boardCustoms,
                style: .custom
            )
            historyColumn(
                title: L10n.FocusTimer.colOvertime,
                badge: L10n.FocusTimer.colOvertimeBadge(boardOvers.count),
                tint: Color(red: 0.96, green: 0.62, blue: 0.04),
                records: boardOvers,
                style: .overtime
            )
        }
    }

    private enum ColumnStyle { case preset, custom, overtime }

    private func historyColumn(
        title: String,
        badge: String,
        tint: Color,
        records: [FocusTimerRecord],
        style: ColumnStyle
    ) -> some View {
        let isOvertime = style == .overtime
        let isCustom = style == .custom
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle().fill(tint).frame(width: 10, height: 10)
                Text(title)
                    .font(SettingsChrome.Font.sectionTitle)
                    .fontWeight(isOvertime ? .bold : .semibold)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if isOvertime {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(badge)
                        .font(SettingsChrome.Font.monoCaption)
                        .fontWeight(isCustom || isOvertime ? .semibold : .regular)
                }
                .foregroundStyle(
                    isOvertime
                        ? Color(red: 0.45, green: 0.27, blue: 0.0)
                        : (isCustom ? tint : SettingsChrome.onSurfaceVariant)
                )
                .padding(.horizontal, isOvertime ? 10 : 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(
                            isOvertime
                                ? Color(red: 1.0, green: 0.92, blue: 0.78)
                                : SettingsChrome.surfaceContainer
                        )
                )
            }

            SettingsHairline()

            if records.isEmpty {
                historyEmptyState(style: style, tint: tint)
            } else {
                ForEach(Array(records.prefix(4).enumerated()), id: \.element.id) { index, record in
                    historyRow(record, index: index, style: style, tint: tint)
                }
            }
        }
        .padding(SettingsChrome.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .shadow(color: .black.opacity(isOvertime ? 0.08 : 0.04), radius: isOvertime ? 8 : 6, y: 2)
                .overlay {
                    if isOvertime {
                        RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                            .strokeBorder(Color(red: 0.33, green: 0.88, blue: 0.44).opacity(0.35), lineWidth: 2)
                    }
                }
        )
    }

    /// 三栏空态：色块图标 + 主副文案（对齐稿面；栏目标题不动）。
    private func historyEmptyState(style: ColumnStyle, tint: Color) -> some View {
        let symbol: String = {
            switch style {
            case .preset: return "stopwatch"
            case .custom: return "slider.horizontal.3"
            case .overtime: return "alarm.badge.plus"
            }
        }()
        let title: String = {
            switch style {
            case .preset: return L10n.FocusTimer.historyEmptyPresetTitle
            case .custom: return L10n.FocusTimer.historyEmptyCustomTitle
            case .overtime: return L10n.FocusTimer.historyEmptyOvertimeTitle
            }
        }()
        let hint: String = {
            switch style {
            case .preset: return L10n.FocusTimer.historyEmptyPresetHint
            case .custom: return L10n.FocusTimer.historyEmptyCustomHint
            case .overtime: return L10n.FocusTimer.historyEmptyOvertimeHint
            }
        }()

        return VStack(spacing: 10) {
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
        index: Int,
        style: ColumnStyle,
        tint: Color
    ) -> some View {
        if record.isUntitled || editingRecordID == record.id {
            FocusTimerTitleBackfillCard(
                record: record,
                badgeText: rowBadge(record, index: index, style: style),
                badgeTint: badgeForeground(style: style, tint: tint),
                barTint: style == .overtime ? Color(red: 0.96, green: 0.62, blue: 0.04) : tint,
                suggestedTitles: suggestedTitles(excluding: record.id),
                isEditing: editingRecordID == record.id,
                draft: $titleDraft,
                onBeginEdit: {
                    editingRecordID = record.id
                    titleDraft = ""
                    AppLog.debug("FocusTimer", "看板进入补填", ["id": String(record.id.uuidString.prefix(8))])
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
        } else {
            namedHistoryRow(record, index: index, style: style, tint: tint)
        }
    }

    private func suggestedTitles(excluding id: UUID) -> [String] {
        settings.frequentTitles(limit: 5, excluding: id)
    }

    private func saveBoardTitle(recordID: UUID, title: String) {
        settings.updateRecordTitle(id: recordID, title: title)
    }

    private func namedHistoryRow(
        _ record: FocusTimerRecord,
        index _: Int,
        style: ColumnStyle,
        tint: Color
    ) -> some View {
        // 稿面：左上计划时长 / 中标题 / 右上实际时长；二行时段+状态；进度条；顺延时底行 +加时与达成率。
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                plannedMinutesBadge(record, style: style, tint: tint)
                Text(record.title)
                    .font(SettingsChrome.Font.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(FocusTimerFormatting.clock(record.totalMinutes * 60))
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(
                        record.endedEarly ? SettingsChrome.error : SettingsChrome.onSurface
                    )
            }

            HStack(spacing: 6) {
                Text(timeRange(record))
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 4)
                statusChip(endedEarly: record.endedEarly)
            }

            recordProgressBar(record: record)

            if record.overtimeMinutes > 0 {
                HStack(spacing: 6) {
                    Text(L10n.FocusTimer.overtimePlusMinutes(record.overtimeMinutes))
                        .font(SettingsChrome.Font.monoCaption)
                        .fontWeight(.bold)
                        .foregroundStyle(SettingsChrome.secondary)
                    Spacer(minLength: 4)
                    achievementChip(percent: record.achievementPercent, endedEarly: record.endedEarly)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private func plannedMinutesBadge(
        _ record: FocusTimerRecord,
        style: ColumnStyle,
        tint: Color
    ) -> some View {
        let isCustom = style == .custom
        return Text(L10n.FocusTimer.badgePlannedMinutes(record.plannedMinutes))
            .font(SettingsChrome.Font.monoCaption)
            .fontWeight(.semibold)
            .foregroundStyle(isCustom ? tint : SettingsChrome.onSurface)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isCustom
                            ? tint.opacity(0.15)
                            : SettingsChrome.surfaceContainer
                    )
            )
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

    private func achievementChip(percent: Int, endedEarly: Bool) -> some View {
        Text(L10n.FocusTimer.achievePercent(percent))
            .font(SettingsChrome.Font.monoCaption)
            .fontWeight(.bold)
            .foregroundStyle(
                endedEarly
                    ? SettingsChrome.error
                    : Color(red: 0.45, green: 0.27, blue: 0.0)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        endedEarly
                            ? SettingsChrome.error.opacity(0.12)
                            : Color(red: 1.0, green: 0.90, blue: 0.70).opacity(0.85)
                    )
            )
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

    private func rowBadge(_ record: FocusTimerRecord, index: Int, style: ColumnStyle) -> String {
        // 补填卡与具名行统一：左上角展示开钟计划时长。
        _ = index
        _ = style
        return L10n.FocusTimer.badgePlannedMinutes(record.plannedMinutes)
    }

    private func badgeForeground(style: ColumnStyle, tint: Color) -> Color {
        switch style {
        case .custom: return tint
        case .overtime: return SettingsChrome.onSurface
        case .preset: return SettingsChrome.onSurface
        }
    }

    private func badgeBackground(style: ColumnStyle, tint: Color) -> Color {
        switch style {
        case .custom: return tint.opacity(0.15)
        default: return SettingsChrome.surfaceContainer
        }
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
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? SettingsChrome.cardBackground : Color.clear)
                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 1.5, y: 0.5)
                )
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
