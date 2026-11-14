import AppKit
import SwiftUI

/// 设置「专注与击键」：击键、焦点切换、24h 时间线、年热力。从资源监控页拆出，样式保持不变。
struct ResourceFocusInsightsPane: View {
    @ObservedObject private var session = ResourceMonitorSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPermissionCard(
                    status: session.inputMonitoringGranted ? .authorized : .request,
                    symbol: "hand.raised.fill",
                    tint: Color(red: 0.42, green: 0.30, blue: 0.86),
                    title: L10n.ResourceMonitor.permissionAccess,
                    subtitle: L10n.ResourceMonitor.permissionAccessDesc,
                    requestTitle: L10n.ResourceMonitor.requestPermission,
                    action: { session.requestInputMonitoring() }
                )
                metricsRow
                behaviorCard
                heatmapCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            guard MenuBarController.shared?.settingsWindow != nil else { return }
            session.start()
            session.setSettingsVisible(true)
            session.refreshInputMonitoringStatus()
            IslandController.shared?.beginSettingsSessionCollapsed()
            AppLog.info("ResourceMonitor", "专注与击键页已显示", [
                "keys": session.todayKeystrokes,
                "switches": session.todaySwitches,
                "inputMonitoring": session.inputMonitoringGranted
            ])
        }
        .onDisappear {
            session.setSettingsVisible(false)
        }
    }

    private var deepFocusBlue: Color { Color(red: 0.0, green: 0.22, blue: 0.58) }
    private var keystrokePurple: Color { Color(red: 0.42, green: 0.30, blue: 0.86) }
    private var deepRAMRed: Color { Color(red: 0.72, green: 0.08, blue: 0.10) }


    private var metricsRow: some View {
        let hourlySwitches = focusSwitchesPerHour(session.todaySwitches)
        let switchPercent = min(100, hourlySwitches)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
            spacing: 12
        ) {
            metricCard(
                title: L10n.ResourceMonitor.keystrokeCard,
                icon: "keyboard",
                major: formatCount(session.todayKeystrokes),
                minor: L10n.ResourceMonitor.keysUnit,
                barPercent: min(100, Double(session.todayKeystrokes) / 300),
                tint: keystrokePurple,
                badge: .trendIcon,
                footnote: session.inputMonitoringGranted
                    ? (session.keystrokePeakRangeText.map(L10n.ResourceMonitor.keystrokePeak)
                        ?? L10n.ResourceMonitor.keystrokePeakPlaceholder)
                    : L10n.ResourceMonitor.keystrokeNeedPermission
            )
            metricCard(
                title: L10n.ResourceMonitor.switchCard,
                icon: "arrow.left.arrow.right",
                major: "\(session.todaySwitches)",
                minor: L10n.ResourceMonitor.switchesUnit,
                barPercent: switchPercent,
                tint: deepFocusBlue,
                badge: .textPlain(L10n.ResourceMonitor.todayCumulative),
                footnote: focusSwitchFootnote(hourly: hourlySwitches)
            )
        }
    }

    private enum MetricBadgeStyle {
        case soft
        case plain
        case critical
    }

    private enum MetricBadge {
        case percent(Double, style: MetricBadgeStyle)
        /// 有底色灰徽章（少用）。
        case text(String)
        /// 着色、无背景（交换 / CPU / 焦点右上角）。
        case textPlain(String)
        case trendIcon
    }

    private func metricCard(
        title: String,
        icon: String,
        major: String,
        minor: String,
        barPercent: Double,
        tint: Color,
        badge: MetricBadge,
        footnote: String?,
        footnoteTint: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 4)
                metricBadgeView(badge, tint: tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(major)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(SettingsChrome.onSurface)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(minor)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettingsChrome.surfaceContainer)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, barPercent / 100))))
                }
            }
            .frame(height: 6)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(footnoteTint ?? SettingsChrome.onSurfaceVariant)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(" ")
                    .font(.system(size: 11))
                    .hidden()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(cardChrome)
    }

    @ViewBuilder
    private func metricBadgeView(_ badge: MetricBadge, tint: Color) -> some View {
        switch badge {
        case .percent(let value, let style):
            let text = Text(String(format: "%.0f%%", min(100, value)))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            switch style {
            case .plain:
                text.foregroundStyle(tint)
            case .soft:
                text
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
            case .critical:
                text
                    .foregroundStyle(deepRAMRed)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(deepRAMRed.opacity(0.14))
                    )
            }
        case .text(let label):
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(SettingsChrome.surfaceContainer)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .textPlain(let label):
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .trendIcon:
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(keystrokePurple)
                .accessibilityLabel(L10n.ResourceMonitor.keystrokeCard)
        }
    }

    /// 今日焦点切换折算「平均每小时」；当天已过时长至少按 6 分钟计，避免凌晨虚高。
    private func focusSwitchesPerHour(_ todayCount: Int) -> Double {
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let hours = max(now.timeIntervalSince(start) / 3600, 0.1)
        return Double(todayCount) / hours
    }

    /// 三档（次/小时）：0～80 良好 · 81～180 中等 · >180 高频。
    private func focusSwitchFootnote(hourly: Double) -> String {
        let rate = Int(hourly.rounded())
        let level: String
        switch hourly {
        case ...80:
            level = L10n.ResourceMonitor.focusLevelGood
        case ...180:
            level = L10n.ResourceMonitor.focusLevelMid
        default:
            level = L10n.ResourceMonitor.focusLevelBusy
        }
        return L10n.ResourceMonitor.focusSwitchFootnote(rate, level)
    }
    // MARK: - Behavior / heatmap

    private var behaviorCard: some View {
        let ranks = session.focusRanks
        let timeline = session.focusTimeline
        // 时序上出现的 App 都分配调色板色，禁止落到「灰」被当成未知第三态。
        let colorIndexByBundle = Self.focusColorMap(ranks: ranks, timeline: timeline)
        let featuredID = ranks.max(by: { $0.keystrokes < $1.keystrokes })?.bundleID
        // 窗口：今日首次活动 → 现在（随时间变长，跨日清空后重锚）。
        let windowStart = session.focusTimelineAnchor ?? Date()
        let windowEnd = Date()
        let windowSpan = max(30, windowEnd.timeIntervalSince(windowStart))
        let tickDates = Self.timelineTickDates(start: windowStart, end: windowEnd)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(keystrokePurple)
                Text(L10n.ResourceMonitor.behaviorTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsChrome.onSurface)
            }

            Text(L10n.ResourceMonitor.behaviorHint)
                .font(.system(size: 12))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(L10n.ResourceMonitor.focusDistribution)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsChrome.onSurface)
                    } icon: {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    Spacer(minLength: 8)
                    Text(
                        session.focusTimelineAnchor.map(L10n.ResourceMonitor.focusWindowRange)
                            ?? L10n.ResourceMonitor.focusTickNow
                    )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }

                // 真实时序：左端=今日首次使用，右端=现在；底色仅表示长时间无记录（如关机）。
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                            .frame(width: width, height: geo.size.height)
                        ForEach(timeline) { segment in
                            let startOffset = max(0, segment.start.timeIntervalSince(windowStart))
                            let endOffset = min(
                                windowSpan,
                                max(startOffset, segment.end.timeIntervalSince(windowStart))
                            )
                            let x = width * CGFloat(startOffset / windowSpan)
                            let w = width * CGFloat((endOffset - startOffset) / windowSpan)
                            let colorIdx = colorIndexByBundle[segment.bundleID] ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(focusColor(colorIdx).opacity(0.9))
                                .frame(width: max(2, w), height: geo.size.height)
                                .offset(x: x)
                                .help(
                                    "\(segment.name) · \(L10n.ResourceMonitor.focusClock(segment.start))–\(L10n.ResourceMonitor.focusClock(segment.end))"
                                )
                        }
                    }
                }
                .frame(height: 28)
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.surfaceContainer)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    ForEach(Array(tickDates.enumerated()), id: \.offset) { index, date in
                        if index == tickDates.count - 1 {
                            Text(L10n.ResourceMonitor.focusTickNow)
                        } else {
                            Text(L10n.ResourceMonitor.focusClock(date))
                        }
                        if index < tickDates.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.ResourceMonitor.focusRankTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.ResourceMonitor.focusRankBadge)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(SettingsChrome.surfaceContainer)
                        )
                    Spacer(minLength: 6)
                    HStack(spacing: 0) {
                        Text(L10n.ResourceMonitor.focusTodayTotalLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        Text(L10n.ResourceMonitor.durationHours(session.todayFocusTotalSeconds))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SettingsChrome.onSurface)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }

                if ranks.isEmpty {
                    Text(L10n.ResourceMonitor.focusEmptyRank)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(ranks) { rank in
                        focusRankRow(rank, featured: rank.bundleID == featuredID)
                    }
                }
            }
        }
        .padding(14)
        .background(cardChrome)
    }

    @ViewBuilder
    private func focusRankRow(_ rank: ResourceFocusRank, featured: Bool) -> some View {
        let tint = focusColor(rank.colorIndex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: focusCategorySymbol(rank.category))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.15))
                    )
                Text(rank.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                Text(focusCategoryLabel(rank.category))
                    .font(.system(size: 10, design: .monospaced).weight(featured ? .medium : .regular))
                    .foregroundStyle(featured ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            featured
                                ? SettingsChrome.primary.opacity(0.12)
                                : SettingsChrome.surfaceContainerHighest
                        )
                    )
                Spacer(minLength: 6)
                Text(L10n.ResourceMonitor.durationHours(rank.seconds))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.ResourceMonitor.focusSharePercent(rank.sharePercent))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettingsChrome.surfaceContainer)
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, rank.sharePercent / 100))))
                }
            }
            .frame(height: 6)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 4),
                spacing: 6
            ) {
                focusMetricCell(
                    icon: "keyboard",
                    iconTint: tint,
                    title: L10n.ResourceMonitor.focusMetricKeys,
                    value: L10n.ResourceMonitor.focusKeystrokeCount(rank.keystrokes),
                    valueTint: featured ? SettingsChrome.primary : SettingsChrome.onSurface
                )
                focusMetricCell(
                    icon: "arrow.left.arrow.right",
                    iconTint: SettingsChrome.onSurfaceVariant,
                    title: L10n.ResourceMonitor.focusMetricSwitches,
                    value: L10n.ResourceMonitor.focusSwitchCount(rank.switches),
                    valueTint: SettingsChrome.onSurface
                )
                focusMetricCell(
                    icon: "timer",
                    iconTint: SettingsChrome.primary,
                    title: L10n.ResourceMonitor.focusMetricAverage,
                    value: L10n.ResourceMonitor.focusAverageMinutes(rank.averageSessionSeconds),
                    valueTint: SettingsChrome.onSurface
                )
                focusMetricCell(
                    icon: "trophy",
                    iconTint: SettingsChrome.secondary,
                    title: L10n.ResourceMonitor.focusMetricLongest,
                    value: L10n.ResourceMonitor.durationHours(rank.longestSessionSeconds),
                    valueTint: featured ? SettingsChrome.secondary : SettingsChrome.onSurface
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    featured ? SettingsChrome.primary.opacity(0.35) : SettingsChrome.cardStroke,
                    lineWidth: featured ? 1.2 : SettingsChrome.cardStrokeWidth
                )
        )
    }

    private func focusMetricCell(
        icon: String,
        iconTint: Color,
        title: String,
        value: String,
        valueTint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(iconTint)
            }
            .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SettingsChrome.cardBackground.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func focusCategoryLabel(_ category: ResourceFocusCategory) -> String {
        switch category {
        case .browser: return L10n.ResourceMonitor.focusCategoryBrowser
        case .ide: return L10n.ResourceMonitor.focusCategoryIDE
        case .terminal: return L10n.ResourceMonitor.focusCategoryTerminal
        case .systemIdle: return L10n.ResourceMonitor.focusCategorySystemIdle
        case .other: return L10n.ResourceMonitor.focusCategoryOther
        }
    }

    private func focusCategorySymbol(_ category: ResourceFocusCategory) -> String {
        switch category {
        case .browser: return "globe"
        case .ide: return "chevron.left.forwardslash.chevron.right"
        case .terminal: return "terminal"
        case .systemIdle: return "lock.display"
        case .other: return "app"
        }
    }

    private var heatmapCard: some View {
        let days = session.yearDays
        let yearKeys = days.reduce(0) { $0 + $1.keystrokes }
        let streak = activeStreakDays(days)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label {
                    Text(L10n.ResourceMonitor.heatmapTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } icon: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsChrome.primary)
                }
                Spacer(minLength: 6)
                Text(L10n.ResourceMonitor.yearKeys(yearKeys))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
            }

            // 按可用宽度折行；格数 = 首次使用日（或本年 1/1）至今，不裁切、不横向滚。
            ResourceHeatmapCanvas(days: days)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(L10n.ResourceMonitor.heatLow)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                ForEach(0..<5, id: \.self) { band in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(legendBandColor(band))
                        .frame(width: 10, height: 10)
                }
                Text(L10n.ResourceMonitor.heatHigh)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 6)
                Text(L10n.ResourceMonitor.activeStreak(streak))
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardChrome)
    }

    /// 从今天往回连续「有击键或有负荷档」的天数。
    private func activeStreakDays(_ days: [ResourceDayAggregate]) -> Int {
        var streak = 0
        for day in days.reversed() {
            if day.keystrokes > 0 || day.peakRamBand > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// 图例末档为高负荷红，与格点高压态一致。
    private func legendBandColor(_ band: Int) -> Color {
        switch band {
        case 0: return SettingsChrome.surfaceContainer
        case 1: return SettingsChrome.primary.opacity(0.25)
        case 2: return SettingsChrome.primary.opacity(0.45)
        case 3: return SettingsChrome.primary.opacity(0.7)
        default: return deepRAMRed
        }
    }

    // MARK: - Helpers

    private var cardChrome: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(SettingsChrome.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
    }
    private func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    private func focusColor(_ index: Int) -> Color {
        // 全部用鲜明色；不再用灰（易与「无记录」底色混淆）。
        let palette: [Color] = [
            Color(red: 0.92, green: 0.26, blue: 0.21),
            SettingsChrome.primary,
            Color(red: 0.30, green: 0.29, blue: 0.79),
            SettingsChrome.secondary,
            Color(red: 0.90, green: 0.55, blue: 0.12)
        ]
        return palette[index % palette.count]
    }

    /// 排行优先占色，时序里多出来的 App 依次接调色板。
    private static func focusColorMap(
        ranks: [ResourceFocusRank],
        timeline: [ResourceFocusTimelineSegment]
    ) -> [String: Int] {
        var map: [String: Int] = [:]
        for rank in ranks {
            map[rank.bundleID] = rank.colorIndex
        }
        var next = ranks.count
        for segment in timeline where map[segment.bundleID] == nil {
            map[segment.bundleID] = next % 5
            next += 1
        }
        return map
    }

    /// 时序刻度：起点…均匀中间点…终点（终点在 UI 显示为「现在」）。
    private static func timelineTickDates(start: Date, end: Date) -> [Date] {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return [start, end] }
        if span < 5 * 60 {
            return [start, end]
        }
        if span < 30 * 60 {
            return [start, start.addingTimeInterval(span / 2), end]
        }
        return [0.0, 0.25, 0.5, 0.75, 1.0].map { start.addingTimeInterval(span * $0) }
    }

}

/// 按日横排热力：AppKit 单视图绘制 + 本地浮层日期，避免 SwiftUI 悬停刷状态卡死。
private struct ResourceHeatmapCanvas: NSViewRepresentable {
    let days: [ResourceDayAggregate]

    func makeNSView(context: Context) -> ResourceHeatmapNSView {
        let view = ResourceHeatmapNSView()
        view.days = days
        return view
    }

    func updateNSView(_ nsView: ResourceHeatmapNSView, context: Context) {
        guard nsView.days != days else { return }
        nsView.days = days
        nsView.needsDisplay = true
        nsView.invalidateIntrinsicContentSize()
    }
}

private final class ResourceHeatmapNSView: NSView {
    var days: [ResourceDayAggregate] = [] {
        didSet { hideTip() }
    }

    private let cellSize: CGFloat = 10
    private let gap: CGFloat = 3
    private var tipBubble: NSView!
    private var tipLabel: NSTextField!
    private var lastLayoutWidth: CGFloat = -1

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        // 气泡可盖住上方标题，不额外撑开与标题的间距。
        layer?.masksToBounds = false

        let bubble = NSView(frame: .zero)
        bubble.wantsLayer = true
        bubble.isHidden = true
        bubble.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        bubble.layer?.cornerRadius = 6
        bubble.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.isBezeled = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        bubble.addSubview(label)

        addSubview(bubble)
        tipBubble = bubble
        tipLabel = label
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 1 ? bounds.width : 240
        return NSSize(width: NSView.noIntrinsicMetric, height: metrics(forWidth: width).height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        relaxClippingAncestors()
    }

    override func layout() {
        super.layout()
        relaxClippingAncestors()
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// 让气泡能盖住上方标题，不被 SwiftUI / AppKit 祖先裁切。
    private func relaxClippingAncestors() {
        var node: NSView? = self
        var depth = 0
        while let view = node, depth < 8 {
            view.clipsToBounds = false
            view.layer?.masksToBounds = false
            if view is NSScrollView { break }
            node = view.superview
            depth += 1
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        let m = metrics(forWidth: bounds.width)
        let corner = max(1.5, cellSize * 0.18)
        for (index, day) in days.enumerated() {
            let row = index / m.cols
            let col = index % m.cols
            let x = CGFloat(col) * (cellSize + gap)
            let y = CGFloat(row) * (cellSize + gap)
            let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
            let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
            Self.nsColor(for: day).setFill()
            path.fill()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = cellHit(at: point) else {
            hideTip()
            return
        }
        tipLabel.stringValue = hit.tip
        tipLabel.sizeToFit()
        let padX: CGFloat = 8
        let padY: CGFloat = 4
        let bubbleSize = NSSize(
            width: tipLabel.frame.width + padX * 2,
            height: tipLabel.frame.height + padY * 2
        )
        tipLabel.frame = NSRect(
            x: padX,
            y: padY,
            width: tipLabel.frame.width,
            height: tipLabel.frame.height
        )
        // 严格锚在当前格子水平中心正上方；不夹到画布边缘（否则前几格看起来位置不变）。
        let origin = NSPoint(
            x: hit.rect.midX - bubbleSize.width / 2,
            y: hit.rect.minY - bubbleSize.height - 4
        )
        tipBubble.frame = NSRect(origin: origin, size: bubbleSize)
        tipBubble.isHidden = false
        tipBubble.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hideTip()
    }

    override func mouseDown(with event: NSEvent) {
        // 不抢焦点、不冒泡处理，避免设置页卡顿。
    }

    private func hideTip() {
        tipBubble?.isHidden = true
    }

    private struct CellHit {
        var tip: String
        var rect: NSRect
    }

    private func cellHit(at point: NSPoint) -> CellHit? {
        let m = metrics(forWidth: bounds.width)
        guard m.cols > 0, point.x >= 0, point.y >= 0 else { return nil }
        let col = Int(point.x / (cellSize + gap))
        let row = Int(point.y / (cellSize + gap))
        guard col >= 0, col < m.cols, row >= 0 else { return nil }
        let inCellX = point.x - CGFloat(col) * (cellSize + gap)
        let inCellY = point.y - CGFloat(row) * (cellSize + gap)
        guard inCellX <= cellSize, inCellY <= cellSize else { return nil }
        let index = row * m.cols + col
        guard days.indices.contains(index) else { return nil }
        let rect = NSRect(
            x: CGFloat(col) * (cellSize + gap),
            y: CGFloat(row) * (cellSize + gap),
            width: cellSize,
            height: cellSize
        )
        return CellHit(tip: Self.dayTip(days[index].dayKey), rect: rect)
    }

    private struct Metrics {
        var cols: Int
        var height: CGFloat
    }

    private func metrics(forWidth width: CGFloat) -> Metrics {
        let count = max(1, days.count)
        let usable = max(width, cellSize)
        var cols = max(1, Int(floor((usable + gap) / (cellSize + gap))))
        cols = min(cols, count)
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        let height = CGFloat(rows) * cellSize + CGFloat(max(0, rows - 1)) * gap
        return Metrics(cols: cols, height: height)
    }

    private static func dayTip(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return dayKey }
        return L10n.ResourceMonitor.heatmapDayLabel(month: month, day: day)
    }

    static func activityBand(for day: ResourceDayAggregate) -> Int {
        switch day.keystrokes {
        case 0: return 0
        case 1..<500: return 1
        case 500..<2_000: return 2
        case 2_000..<5_000: return 3
        default: return 4
        }
    }

    static func color(for day: ResourceDayAggregate) -> Color {
        Color(nsColor: nsColor(for: day))
    }

    private static func nsColor(for day: ResourceDayAggregate) -> NSColor {
        let hot = NSColor(red: 0.72, green: 0.08, blue: 0.10, alpha: 1)
        switch activityBand(for: day) {
        case 0:
            return NSColor(red: 0.937, green: 0.937, blue: 0.949, alpha: 1)
        case 1:
            return NSColor(SettingsChrome.primary).withAlphaComponent(0.25)
        case 2:
            return NSColor(SettingsChrome.primary).withAlphaComponent(0.45)
        case 3:
            return NSColor(SettingsChrome.primary).withAlphaComponent(0.7)
        default:
            return hot
        }
    }
}

extension ResourceDayAggregate: Identifiable {
    var id: String { dayKey }
}
