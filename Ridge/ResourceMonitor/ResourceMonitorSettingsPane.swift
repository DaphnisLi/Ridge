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
                    topAppsCard
                    VStack(alignment: .leading, spacing: 12) {
                        behaviorCard
                        heatmapCard
                    }
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
                    ? L10n.ResourceMonitor.keystrokePeakPlaceholder
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
        let slices = session.focusSlices
        let totalFocus = max(1, slices.reduce(0) { $0 + $1.seconds })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(keystrokePurple)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.ResourceMonitor.behaviorTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.ResourceMonitor.behaviorHint)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L10n.ResourceMonitor.focusDistribution)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 8)
                Text(L10n.ResourceMonitor.focusWindowNow)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    if slices.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SettingsChrome.surfaceContainer)
                            .frame(width: geo.size.width)
                    } else {
                        ForEach(slices) { slice in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(focusColor(slice.colorIndex))
                                .frame(width: max(6, geo.size.width * CGFloat(slice.seconds / totalFocus)))
                                .help("\(slice.name) · \(L10n.ResourceMonitor.durationHours(slice.seconds))")
                        }
                    }
                }
            }
            .frame(height: 28)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading),
                    GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(focusColor(slice.colorIndex)).frame(width: 8, height: 8)
                        Text("\(slice.name) (\(L10n.ResourceMonitor.durationHours(slice.seconds)))")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurface)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ResourceRAMWaveChart(
                samples: session.ramSamples,
                thresholdPercent: settings.ramThresholdPercent,
                currentPercent: session.snapshot.ramPercent,
                accent: SettingsChrome.primary,
                critical: deepRAMRed
            )
            .padding(.top, 4)
        }
        .padding(14)
        .background(cardChrome)
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

            // 按可用宽度折行，多加几行把 365 天全铺开，不裁切、不横向滚。
            ResourceHeatmapCanvas(days: days)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                        .onChange(of: ramThresholdDraft) { _, _ in
                            // 仅允许数字；提交时再钳制范围。
                            let filtered = ramThresholdDraft.filter(\.isNumber)
                            if filtered != ramThresholdDraft { ramThresholdDraft = filtered }
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

    /// 提交 RAM 阈值：默认 85，合法范围 50…99。
    private func commitRamThreshold() {
        let raw = Int(ramThresholdDraft) ?? Int(settings.ramThresholdPercent.rounded())
        let clamped = min(99, max(50, raw))
        if abs(settings.ramThresholdPercent - Double(clamped)) > 0.01 {
            settings.ramThresholdPercent = Double(clamped)
            AppLog.info("ResourceMonitor", "用户修改 RAM 告警阈值", ["percent": clamped])
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
        let palette: [Color] = [
            Color(red: 0.92, green: 0.26, blue: 0.21),
            SettingsChrome.primary,
            Color(red: 0.30, green: 0.29, blue: 0.79),
            SettingsChrome.secondary,
            SettingsChrome.onSurfaceVariant
        ]
        return palette[index % palette.count]
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

/// 按日横排热力：第一行画满再折第二行；格子均分宽度，行距均匀。
private struct ResourceHeatmapCanvas: View {
    let days: [ResourceDayAggregate]

    private let preferredCell: CGFloat = 10
    private let gap: CGFloat = 3
    @State private var canvasWidth: CGFloat = 0

    var body: some View {
        let metrics = Self.layout(
            dayCount: days.count,
            width: max(canvasWidth, 1),
            preferredCell: preferredCell,
            gap: gap
        )
        Canvas { context, _ in
            let cell = metrics.cell
            let cols = metrics.cols
            for (index, day) in days.enumerated() {
                let row = index / cols
                let col = index % cols
                let x = CGFloat(col) * (cell + gap)
                let y = CGFloat(row) * (cell + gap)
                let rect = CGRect(x: x, y: y, width: cell, height: cell)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: max(1.5, cell * 0.18)),
                    with: .color(Self.color(for: day))
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: metrics.height, maxHeight: metrics.height, alignment: .topLeading)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { canvasWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        canvasWidth = newWidth
                    }
            }
        )
    }

    private struct LayoutMetrics {
        var cols: Int
        var cell: CGFloat
        var height: CGFloat
    }

    private static func layout(
        dayCount: Int,
        width: CGFloat,
        preferredCell: CGFloat,
        gap: CGFloat
    ) -> LayoutMetrics {
        let count = max(1, dayCount)
        let usable = max(width, preferredCell)
        var cols = max(1, Int(floor((usable + gap) / (preferredCell + gap))))
        cols = min(cols, count)
        let cell = max(6, (usable - CGFloat(max(0, cols - 1)) * gap) / CGFloat(cols))
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        let height = CGFloat(rows) * cell + CGFloat(max(0, rows - 1)) * gap
        return LayoutMetrics(cols: cols, cell: cell, height: height)
    }

    /// 活跃度分档（图例 5 格）：只按当日击键，与 RAM 无关。
    static func activityBand(for day: ResourceDayAggregate) -> Int {
        switch day.keystrokes {
        case 0: return 0
        case 1..<500: return 1
        case 500..<2_000: return 2
        case 2_000..<5_000: return 3
        default: return 4 // ≥5000
        }
    }

    static func color(for day: ResourceDayAggregate) -> Color {
        let hot = Color(red: 0.72, green: 0.08, blue: 0.10)
        switch activityBand(for: day) {
        case 0: return SettingsChrome.surfaceContainer
        case 1: return SettingsChrome.primary.opacity(0.25)
        case 2: return SettingsChrome.primary.opacity(0.45)
        case 3: return SettingsChrome.primary.opacity(0.7)
        default: return hot
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

/// 今日 RAM 消耗波形（GB）：峰值标注、阈值虚线、时轴、「现在 / 高危」。
private struct ResourceRAMWaveChart: View {
    let samples: [ResourceRAMSample]
    let thresholdPercent: Double
    let currentPercent: Double
    let accent: Color
    let critical: Color

    var body: some View {
        let peak = samples.max(by: { $0.usedGB < $1.usedGB })
        let hotNow = currentPercent >= thresholdPercent
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.ResourceMonitor.ramWave)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 8)
                if let peak {
                    Text(L10n.ResourceMonitor.ramWavePeak(peak.usedGB, Self.timeLabel(peak.at)))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(critical)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow)
                chartCanvas
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            .frame(height: 88)

            HStack {
                ForEach(axisLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    if label != axisLabels.last { Spacer(minLength: 0) }
                }
                Spacer(minLength: 8)
                Text(hotNow ? L10n.ResourceMonitor.ramWaveNowCritical : L10n.ResourceMonitor.ramWaveNowSafe)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hotNow ? critical : SettingsChrome.onSurfaceVariant)
            }
        }
    }

    private var chartCanvas: some View {
        GeometryReader { geo in
            let maxGB = max(samples.map(\.usedGB).max() ?? 1, 1)
            // 用最近采样反推物理总量，阈值线对齐「物理 RAM 占用」百分比阈值。
            let totalGB: Double = {
                if let last = samples.last, last.percent > 1 {
                    return max(last.usedGB / (last.percent / 100.0), maxGB)
                }
                return maxGB
            }()
            let thresholdGB = totalGB * (thresholdPercent / 100.0)
            let yMax = max(maxGB * 1.05, thresholdGB * 1.05, 1)
            let pts = points(in: geo.size, yMax: yMax)
            ZStack {
                if pts.count >= 2 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                        if let last = pts.last, let first = pts.first {
                            path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                            path.addLine(to: CGPoint(x: first.x, y: geo.size.height))
                            path.closeSubpath()
                        }
                    }
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(accent, lineWidth: 1.6)
                }

                let y = geo.size.height * (1 - CGFloat(thresholdGB / yMax))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(critical.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    private var axisLabels: [String] {
        guard let first = samples.first?.at, let last = samples.last?.at else {
            return ["—"]
        }
        let span = max(last.timeIntervalSince(first), 1)
        let marks = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        return marks.map { Self.timeLabel(first.addingTimeInterval(span * $0)) }
    }

    private func points(in size: CGSize, yMax: Double) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let step = size.width / CGFloat(max(1, samples.count - 1))
        return samples.enumerated().map { index, sample in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height * (1 - CGFloat(sample.usedGB / yMax))
            )
        }
    }

    private static func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

extension ResourceDayAggregate: Identifiable {
    var id: String { dayKey }
}
