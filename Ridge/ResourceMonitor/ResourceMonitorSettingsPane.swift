import AppKit
import SwiftUI

/// 设置「资源监控」页：对齐稿面布局；采样由 Session 后台降频驱动。
struct ResourceMonitorSettingsPane: View {
    @ObservedObject private var session = ResourceMonitorSession.shared
    @ObservedObject private var settings = ResourceMonitorSettings.shared
    /// RAM 告警阈值输入草稿（整数百分比）。
    @State private var ramThresholdDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let banner = session.lastActionBanner {
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsChrome.secondary)
                }
                metricsGrid
                // 左进程约 3/5、右栏约 2/5；不用 ScrollView 内 containerRelativeFrame（易布局死循环卡死）。
                ResourceMonitorRatioSplit(leftFraction: 0.6, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        topAppsCard
                        heatmapCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    behaviorCard
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                alertPolicyBar
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            // 预热隐藏窗不进会话、不抢岛。
            guard MenuBarController.shared?.settingsWindow != nil else { return }
            session.start()
            session.setSettingsVisible(true)
            session.refreshInputMonitoringStatus()
            IslandController.shared?.beginSettingsSessionCollapsed()
            ramThresholdDraft = "\(Int(settings.ramThresholdPercent.rounded()))"
            AppLog.info("ResourceMonitor", "设置页已显示", [
                "ram%": String(format: "%.1f", session.snapshot.ramPercent),
                "apps": session.snapshot.topApps.count,
                "inputMonitoring": session.inputMonitoringGranted,
                "threshold": settings.ramThresholdPercent
            ])
        }
        .onDisappear {
            session.setSettingsVisible(false)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.primary)
                        )
                    Text(L10n.ResourceMonitor.pageTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    if session.snapshot.ramPercent >= settings.ramThresholdPercent {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(SettingsChrome.error)
                                .frame(width: 6, height: 6)
                            Text(L10n.ResourceMonitor.highPressure)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(SettingsChrome.error)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(SettingsChrome.error.opacity(0.12)))
                    }
                }
                HStack(spacing: 6) {
                    Text(L10n.ResourceMonitor.pageSubtitle)
                    Text("·")
                        .foregroundStyle(SettingsChrome.outline)
                    Text(L10n.ResourceMonitor.sampleInterval)
                        .font(.system(size: 12, design: .monospaced))
                }
                .font(.system(size: 12))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                permissionButton
                Button {
                    session.muteAlerts30m()
                } label: {
                    Label(L10n.ResourceMonitor.muteAlert, systemImage: "bell.slash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsChrome.onSurface)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.surfaceContainer)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    session.purgeMemory()
                } label: {
                    Label(
                        session.isPurging ? L10n.ResourceMonitor.purging : L10n.ResourceMonitor.purgeButton,
                        systemImage: "trash"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SettingsChrome.primary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(session.isPurging)
            }
        }
    }

    private var permissionButton: some View {
        let granted = session.inputMonitoringGranted
        return Button {
            guard !granted else { return }
            session.requestInputMonitoring()
        } label: {
            Label(
                granted ? L10n.ResourceMonitor.permissionGranted : L10n.ResourceMonitor.requestPermission,
                systemImage: granted ? "checkmark.shield.fill" : "hand.raised.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(granted ? SettingsChrome.secondary : SettingsChrome.onSurface)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        granted
                            ? SettingsChrome.secondary.opacity(0.14)
                            : SettingsChrome.surfaceContainer
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(granted)
        .help(granted ? L10n.ResourceMonitor.permissionGranted : L10n.ResourceMonitor.requestPermission)
    }

    // MARK: - Metrics

    /// 高压 RAM 用更深的红，避免浅珊瑚像「强调不够」。
    private var deepRAMRed: Color { Color(red: 0.72, green: 0.08, blue: 0.10) }
    /// Swap / CPU 进度条与图标加深，避免发灰发浅。
    private var deepSwapBlue: Color { Color(red: 0.0, green: 0.32, blue: 0.72) }
    /// 比交换蓝更深一档。
    private var deepFocusBlue: Color { Color(red: 0.0, green: 0.22, blue: 0.58) }
    private var deepCPUGreen: Color { Color(red: 0.05, green: 0.48, blue: 0.20) }
    private var keystrokePurple: Color { Color(red: 0.42, green: 0.30, blue: 0.86) }

    private var metricsGrid: some View {
        let snap = session.snapshot
        let ramHot = snap.ramPercent >= settings.ramThresholdPercent
        let hourlySwitches = focusSwitchesPerHour(session.todaySwitches)
        let switchPercent = min(100, hourlySwitches)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
            spacing: 12
        ) {
            metricCard(
                title: L10n.ResourceMonitor.ramCard,
                icon: "memorychip",
                major: gbNumber(snap.ramUsedBytes),
                minor: "/ \(gbNumber(snap.ramTotalBytes)) GB",
                barPercent: snap.ramPercent,
                tint: ramHot ? deepRAMRed : SettingsChrome.primary,
                badge: .percent(snap.ramPercent, style: ramHot ? .critical : .soft),
                footnote: ramHot
                    ? "\(L10n.ResourceMonitor.criticalOverload) (\(L10n.ResourceMonitor.thresholdHint(Int(settings.ramThresholdPercent.rounded()))))"
                    : L10n.ResourceMonitor.thresholdHint(Int(settings.ramThresholdPercent.rounded())),
                footnoteTint: ramHot ? deepRAMRed : nil
            )
            metricCard(
                title: L10n.ResourceMonitor.swapCard,
                icon: "arrow.left.arrow.right.circle",
                major: gbNumber(snap.swapUsedBytes),
                minor: "/ \(gbNumber(snap.swapTotalBytes)) GB",
                barPercent: snap.swapPercent,
                tint: deepSwapBlue,
                badge: .percent(snap.swapPercent, style: .plain),
                footnote: ssdPressureFootnote(snap.swapPercent)
            )
            metricCard(
                title: L10n.ResourceMonitor.cpuCard,
                icon: "gauge.with.dots.needle.33percent",
                major: String(format: "%.1f", snap.cpuPercent),
                minor: "%",
                barPercent: snap.cpuPercent,
                tint: deepCPUGreen,
                badge: .textPlain(ResourceChipInfo.performanceCoresLabel),
                footnote: ResourceChipInfo.cpuFootnote(celsius: snap.cpuCelsius)
            )
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

    /// Swap 落在 SSD：用交换占用近似 SSD 读写压力文案。
    private func ssdPressureFootnote(_ swapPercent: Double) -> String {
        switch swapPercent {
        case ..<40: return L10n.ResourceMonitor.ssdPressureLow
        case ..<70: return L10n.ResourceMonitor.ssdPressureMid
        default: return L10n.ResourceMonitor.ssdPressureHigh
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

    // MARK: - Top apps + island preview

    private var topAppsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label {
                        Text(L10n.ResourceMonitor.topAppsTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                    } icon: {
                        ResourceHierarchyGlyph()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(SettingsChrome.primary)
                    }
                    Button {
                        guard session.expandedAppID != nil else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            session.collapseExpandedHierarchy()
                        }
                        AppLog.info("ResourceMonitor", "折叠层级视图")
                    } label: {
                        Text(L10n.ResourceMonitor.collapseHierarchy)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SettingsChrome.surfaceContainerHighest)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(session.expandedAppID == nil)
                    .opacity(session.expandedAppID == nil ? 0.55 : 1)
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Text(L10n.ResourceMonitor.sortByRSS)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                }

                if session.snapshot.topApps.isEmpty {
                    Text(L10n.ResourceMonitor.emptyTop)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(session.snapshot.topApps.enumerated()), id: \.element.id) { index, app in
                            appRow(app, isTopMemory: index == 0)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // 贴左右与底边的状态条，不是内嵌小卡片。
            HStack(spacing: 8) {
                Text(
                    L10n.ResourceMonitor.processesMonitored(
                        session.snapshot.monitoredProcessCount,
                        session.snapshot.kernelProcessCount
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    ResourceLiveBlinkDot()
                    Text(L10n.ResourceMonitor.liveDispatch)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsChrome.surfaceContainerLow)
        }
        .background(SettingsChrome.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
    }

    private func appRow(_ app: ResourceAppUsage, isTopMemory: Bool) -> some View {
        let expanded = session.expandedAppID == app.id && !app.children.isEmpty
        let memoryHot = isTopMemory
            || app.memoryBytes > UInt64(settings.singleAppAlertGB * 1024 * 1024 * 1024)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // 加宽左侧热区，不抬高整行。
                Group {
                    if !app.children.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                session.toggleExpandedApp(app.id)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 32, height: 28)
                    }
                }

                appIcon(for: app.bundleID)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                            .lineLimit(1)
                        if app.childCount > 0 {
                            Text(L10n.ResourceMonitor.childCount(app.childCount))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(SettingsChrome.surfaceContainerHighest))
                        }
                    }
                    Text("PID \(formatPID(app.mainPID))")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(byteString(app.memoryBytes))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(memoryHot ? deepRAMRed : SettingsChrome.onSurface)
                    Text(String(format: "CPU %.1f%%", app.cpuPercent))
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
                Button {
                    session.killApp(app)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.ResourceMonitor.kill)
            }
            .padding(10)

            if expanded {
                let rowHeight: CGFloat = 30
                let maxVisible = 5
                let visibleCount = min(maxVisible, app.children.count)
                ScrollView(.vertical, showsIndicators: app.children.count > maxVisible) {
                    VStack(spacing: 0) {
                        ForEach(Array(app.children.enumerated()), id: \.element.id) { index, child in
                            let isLast = index == app.children.count - 1
                            HStack(spacing: 8) {
                                ResourceTreeBranch(isLast: isLast)
                                    .frame(width: 18, height: 18)
                                Text(child.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(SettingsChrome.onSurface)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text("PID \(formatPID(child.pid))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                    .layoutPriority(1)
                                Spacer(minLength: 6)
                                Text(byteString(child.memoryBytes))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(SettingsChrome.onSurface)
                                    .layoutPriority(1)
                                Text(String(format: "%.1f%%", child.cpuPercent))
                                    .font(.system(size: 10))
                                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                    .frame(width: 40, alignment: .trailing)
                                if child.canKill {
                                    Button {
                                        session.killChild(child)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(deepRAMRed.opacity(0.9))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 28)
                            .padding(.trailing, 10)
                            .frame(height: rowHeight, alignment: .center)
                        }
                    }
                }
                .frame(height: CGFloat(visibleCount) * rowHeight)
                .padding(.bottom, 8)
                .background(Color.white.opacity(0.55))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private func appIcon(for bundleID: String) -> some View {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        return Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .foregroundStyle(SettingsChrome.primary)
            }
        }
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
        case .other: return L10n.ResourceMonitor.focusCategoryOther
        }
    }

    private func focusCategorySymbol(_ category: ResourceFocusCategory) -> String {
        switch category {
        case .browser: return "globe"
        case .ide: return "chevron.left.forwardslash.chevron.right"
        case .terminal: return "terminal"
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

    // MARK: - Alert

    private var alertPolicyBar: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SettingsChrome.error)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n.ResourceMonitor.alertPolicyTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(settings.alertEnabled ? L10n.ResourceMonitor.alertActive : L10n.ResourceMonitor.alertInactive)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(settings.alertEnabled ? .white : SettingsChrome.onSurfaceVariant)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(settings.alertEnabled ? SettingsChrome.error : SettingsChrome.surfaceContainer)
                        )
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(L10n.ResourceMonitor.alertPolicyBeforeThreshold)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    TextField(L10n.ResourceMonitor.ramThresholdField, text: $ramThresholdDraft)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 40)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(SettingsChrome.error.opacity(0.35), lineWidth: 1)
                        )
                        .textFieldStyle(.plain)
                        .onSubmit { commitRamThreshold() }
                        .onChange(of: ramThresholdDraft) { _, newValue in
                            let filtered = newValue.filter(\.isNumber)
                            if filtered != newValue {
                                ramThresholdDraft = filtered
                                return
                            }
                            // 已是合法阈值则即时写入，无需回车。
                            applyRamThresholdIfComplete(filtered)
                        }
                    Text(L10n.ResourceMonitor.alertPolicyAfterThreshold(settings.singleAppAlertGB))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
            }

            Spacer(minLength: 8)

            Toggle(isOn: Binding(
                get: { settings.alertEnabled },
                set: { session.setAlertEnabled($0) }
            )) {
                Text(L10n.ResourceMonitor.alertToggle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsChrome.error.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SettingsChrome.error.opacity(0.18), lineWidth: 1)
                )
        )
        .onChange(of: settings.ramThresholdPercent) { _, value in
            let next = "\(Int(value.rounded()))"
            if ramThresholdDraft != next { ramThresholdDraft = next }
        }
    }

    /// 输入过程中：仅当草稿已是 50…99 时立刻生效。
    private func applyRamThresholdIfComplete(_ draft: String) {
        guard let n = Int(draft), (50...99).contains(n) else { return }
        guard abs(settings.ramThresholdPercent - Double(n)) > 0.01 else { return }
        settings.ramThresholdPercent = Double(n)
        AppLog.info("ResourceMonitor", "用户修改 RAM 告警阈值", ["percent": n, "via": "typing"])
    }

    /// 回车 / 收尾：钳制到 50…99 并写回草稿。
    private func commitRamThreshold() {
        let raw = Int(ramThresholdDraft) ?? Int(settings.ramThresholdPercent.rounded())
        let clamped = min(99, max(50, raw))
        if abs(settings.ramThresholdPercent - Double(clamped)) > 0.01 {
            settings.ramThresholdPercent = Double(clamped)
            AppLog.info("ResourceMonitor", "用户修改 RAM 告警阈值", ["percent": clamped, "via": "submit"])
        }
        ramThresholdDraft = "\(clamped)"
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

    private func gbNumber(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824.0)
    }

    private func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func byteString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func formatPID(_ pid: Int32) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: pid)) ?? "\(pid)"
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

private extension SettingsChrome {
    static let surfaceContainerHighest = Color(red: 0.894, green: 0.886, blue: 0.894)
}

/// 左右比例分栏（ScrollView 安全；替代 containerRelativeFrame）。
private struct ResourceMonitorRatioSplit: Layout {
    var leftFraction: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count >= 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }
        let width = proposal.width ?? 800
        let leftW = max(0, (width - spacing) * leftFraction)
        let rightW = max(0, width - spacing - leftW)
        let leftSize = subviews[0].sizeThatFits(.init(width: leftW, height: proposal.height))
        let rightSize = subviews[1].sizeThatFits(.init(width: rightW, height: proposal.height))
        return CGSize(width: width, height: max(leftSize.height, rightSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else {
            subviews.first?.place(at: bounds.origin, proposal: .init(width: bounds.width, height: bounds.height))
            return
        }
        let leftW = max(0, (bounds.width - spacing) * leftFraction)
        let rightW = max(0, bounds.width - spacing - leftW)
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

/// Live Dispatch 旁闪光点：更大，透明度 0→1 闪光弹式脉冲。
private struct ResourceLiveBlinkDot: View {
    private let period: TimeInterval = 1.05
    private let green = Color(red: 0.22, green: 0.82, blue: 0.38)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            Circle()
                .fill(green)
                .frame(width: 11, height: 11)
                .opacity(Self.flashOpacity(at: context.date, period: period))
                .shadow(
                    color: green.opacity(Self.flashOpacity(at: context.date, period: period) * 0.55),
                    radius: 3
                )
        }
        .accessibilityHidden(true)
    }

    /// 前段迅速 0→1，后段掉回 0，再短暂熄灭（闪光弹）。
    private static func flashOpacity(at date: Date, period: TimeInterval) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        if phase < 0.14 { return phase / 0.14 }
        if phase < 0.42 { return 1.0 - (phase - 0.14) / 0.28 }
        return 0
    }
}

/// Top 5 标题旁的层级树图标（对齐稿面）。
private struct ResourceHierarchyGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let box = s * 0.30
            let lineW = max(1.1, s * 0.08)
            let left = s * 0.12
            let top = s * 0.08
            let midY = s * 0.62
            let right = s * 0.62

            let parent = CGRect(x: left, y: top, width: box, height: box)
            let childL = CGRect(x: left, y: midY, width: box, height: box)
            let childR = CGRect(x: right, y: midY, width: box, height: box)

            var stem = Path()
            stem.move(to: CGPoint(x: parent.midX, y: parent.maxY))
            stem.addLine(to: CGPoint(x: parent.midX, y: childL.midY))
            stem.addLine(to: CGPoint(x: childR.minX, y: childL.midY))
            context.stroke(
                stem,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round)
            )

            for rect in [parent, childL, childR] {
                context.fill(
                    Path(roundedRect: rect, cornerRadius: box * 0.22),
                    with: .foreground
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ResourceTreeBranch: View {
    let isLast: Bool

    var body: some View {
        Canvas { context, size in
            let midX = size.width * 0.45
            var path = Path()
            path.move(to: CGPoint(x: midX, y: 0))
            path.addLine(to: CGPoint(x: midX, y: size.height * (isLast ? 0.55 : 1)))
            path.move(to: CGPoint(x: midX, y: size.height * 0.55))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.55))
            context.stroke(
                path,
                with: .color(SettingsChrome.outline),
                style: StrokeStyle(lineWidth: 1, lineCap: .square)
            )
        }
        .accessibilityHidden(true)
    }
}

extension ResourceDayAggregate: Identifiable {
    var id: String { dayKey }
}
