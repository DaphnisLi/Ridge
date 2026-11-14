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
                topAppsCard
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
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
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

    // MARK: - Metrics

    /// 高压 RAM 用更深的红，避免浅珊瑚像「强调不够」。
    private var deepRAMRed: Color { Color(red: 0.72, green: 0.08, blue: 0.10) }
    /// Swap / CPU 进度条与图标加深，避免发灰发浅。
    private var deepSwapBlue: Color { Color(red: 0.0, green: 0.32, blue: 0.72) }
    private var deepCPUGreen: Color { Color(red: 0.05, green: 0.48, blue: 0.20) }

    private var metricsGrid: some View {
        let snap = session.snapshot
        let ramHot = snap.ramPercent >= settings.ramThresholdPercent
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
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
        /// 着色、无背景（交换 / CPU 右上角）。
        case textPlain(String)
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

    private func byteString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func formatPID(_ pid: Int32) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: pid)) ?? "\(pid)"
    }

}

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

