import SwiftUI

/// 控制台「项目释放」页：左工程树 / 右监视中 + 容器，对齐树形多命令稿。
struct ProjectReleaseDeckView: View {
    @ObservedObject private var session = ProjectReleaseSession.shared
    @State private var containersExpanded = false
    @State private var collapsedProjectIDs: Set<String> = []

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    private let accentCyan = Color(red: 0.024, green: 0.714, blue: 0.831)
    private let accentPurple = Color(red: 0.545, green: 0.361, blue: 0.965)
    private let accentAmber = Color(red: 0.961, green: 0.620, blue: 0.043)
    private let accentPink = Color(red: 0.925, green: 0.282, blue: 0.600)
    private let accentEmerald = Color(red: 0.204, green: 0.827, blue: 0.600)
    private let cardFill = Color(red: 0.071, green: 0.075, blue: 0.106).opacity(0.90)
    private let cardStroke = Color.white.opacity(0.05)
    private let scrollViewportFill = Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 1))
    private let rowFill = Color.black.opacity(0.40)
    private let folderTints: [Color] = [
        Color(red: 0.961, green: 0.620, blue: 0.043),
        Color(red: 0.506, green: 0.447, blue: 0.984),
        Color(red: 0.231, green: 0.510, blue: 0.965),
        Color(red: 0.024, green: 0.714, blue: 0.831),
        Color(red: 0.925, green: 0.282, blue: 0.600)
    ]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let leftW = (geo.size.width - gap) * (7.0 / 12.0)
            let rightW = geo.size.width - gap - leftW
            VStack(alignment: .leading, spacing: 6) {
                if let banner = session.lastActionBanner {
                    Text(banner)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accentEmerald)
                        .lineLimit(1)
                }
                let rightH = max(0, geo.size.height - (session.lastActionBanner == nil ? 0 : 18))
                let containerH = containersExpanded
                    ? rightH
                    : min(rightH, max(96, rightH * 0.34))
                let watchH = containersExpanded
                    ? 0
                    : max(0, rightH - containerH - gap)
                HStack(alignment: .top, spacing: gap) {
                    runningCard
                        .frame(width: leftW, height: rightH, alignment: .topLeading)
                    VStack(spacing: gap) {
                        if !containersExpanded {
                            watchingCard
                                .frame(width: rightW, height: watchH, alignment: .topLeading)
                                .clipped()
                        }
                        containersCard
                            .frame(width: rightW, height: containerH, alignment: .topLeading)
                            .clipped()
                    }
                    .frame(width: rightW, height: rightH, alignment: .top)
                    .animation(.easeInOut(duration: 0.2), value: containersExpanded)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            session.start()
            AppLog.info("Projects", "项目释放页已显示", [
                "groups": session.groups.count,
                "running": session.runningGroups.count,
                "containers": session.containerItems.count,
                "watches": session.watches.count
            ])
        }
        .onChange(of: session.containerItems.count) { _, count in
            // 展开态下容器被全部释放后，「收起」按钮会随空列表消失；改为自动收起。
            guard containersExpanded, count == 0 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                containersExpanded = false
            }
            AppLog.info("Projects", "容器已清空，自动收起列表", ["count": 0])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Projects.deckTitle)
    }

    // MARK: - Running

    private var runningCard: some View {
        let groups = session.runningGroups
        let processTotal = groups.reduce(0) { $0 + $1.items.filter { $0.kind == .process }.count }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Text(L10n.Projects.runningTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                if !groups.isEmpty {
                    Text(L10n.Projects.runningStats(groups.count, processTotal))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accentBlue.opacity(0.20)))
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle()
                        .fill(accentEmerald)
                        .frame(width: 5, height: 5)
                    Text(L10n.Projects.treeStreamLabel)
                        .font(.system(size: 9, weight: .medium).monospaced())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
            }

            if groups.isEmpty {
                emptyHint(L10n.Projects.emptyState)
                Spacer(minLength: 0)
            } else {
                AlwaysVisibleScrollView(viewportFill: scrollViewportFill) {
                    VStack(spacing: 10) {
                        ForEach(groups) { group in
                            runningProject(group)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func runningProject(_ group: ProjectRuntimeGroup) -> some View {
        let name = group.project?.name ?? L10n.Projects.unattributed
        let processItems = group.items.filter { $0.kind == .process }
        let collapsed = collapsedProjectIDs.contains(group.id)
        let tint = folderTint(for: name)
        let cpu = processItems.reduce(0.0) { $0 + $1.cpuPercent }
        let memBytes = processItems.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let mem = ByteCountFormatter.string(fromByteCount: Int64(memBytes), countStyle: .memory)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggleCollapsed(group.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 12)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tint)
                    Text(name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(L10n.Projects.commandCount(processItems.count))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)))
                    Spacer(minLength: 4)
                    Text(L10n.Projects.projectCPU(cpu))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                    Text(mem)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(spacing: 4) {
                    ForEach(processItems.prefix(10)) { item in
                        processRow(item, in: group, projectName: name)
                    }
                    if processItems.count > 10 {
                        Text(L10n.Projects.moreItems(processItems.count - 10))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.30))
                            .padding(.leading, 18)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private func processRow(
        _ item: ProjectRuntimeItem,
        in group: ProjectRuntimeGroup,
        projectName: String
    ) -> some View {
        let watching = session.isWatching(pid: item.pid)
        let busy = item.cpuPercent >= 0.3
        let mem = ByteCountFormatter.string(fromByteCount: Int64(item.memoryBytes), countStyle: .memory)
        return HStack(spacing: 6) {
            treeBranchMark
            Circle()
                .fill(watching ? accentBlue : (busy ? accentEmerald : Color.zinc500))
                .frame(width: 5, height: 5)
                .overlay {
                    if watching {
                        Circle()
                            .fill(accentBlue.opacity(0.55))
                            .frame(width: 5, height: 5)
                            .scaleEffect(watching ? 1.6 : 1)
                            .opacity(0.5)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 11, weight: watching ? .bold : .semibold).monospaced())
                        .foregroundStyle(watching ? Color(red: 0.75, green: 0.85, blue: 1.0) : .white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let port = item.ports.first {
                        Text(":\(port)")
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(portForeground(port))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(portForeground(port).opacity(0.18))
                            )
                    }
                }
                Text(processMetaLine(item, memory: mem))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(watching ? accentBlue.opacity(0.75) : .white.opacity(0.40))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.pid != nil {
                Button {
                    AppLog.info("Projects", "点击监视", [
                        "project": projectName,
                        "command": item.title,
                        "pid": item.pid.map(String.init) ?? "",
                        "watching": !watching
                    ])
                    session.toggleWatch(item: item, projectName: projectName)
                } label: {
                    Group {
                        if watching {
                            HStack(spacing: 2) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(L10n.Projects.watchingActionOn)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(accentBlue))
                        } else {
                            Text(L10n.Projects.watchAction)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.Projects.watchHelp)
            }

            if item.canRelease {
                Button {
                    AppLog.info("Projects", "点击释放", [
                        "project": projectName,
                        "command": item.title,
                        "pid": item.pid.map(String.init) ?? ""
                    ])
                    session.release(item: item, in: group)
                } label: {
                    Text(session.isReleasing(group) ? L10n.Projects.releasing : L10n.Projects.release)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(red: 0.97, green: 0.44, blue: 0.44))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.10))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(session.isReleasing(group))
                .help(L10n.Projects.releaseItemHelp)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(watching ? accentBlue.opacity(0.10) : rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            watching ? accentBlue.opacity(0.30) : Color.white.opacity(0.04),
                            lineWidth: 1
                        )
                )
        )
        // 勿 `.compositingGroup()`：浮层 NSPanel 上会把子 Button 打成不可点。
    }

    private var treeBranchMark: some View {
        Path { path in
            path.move(to: CGPoint(x: 4, y: 0))
            path.addLine(to: CGPoint(x: 4, y: 10))
            path.addLine(to: CGPoint(x: 10, y: 10))
        }
        .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        .frame(width: 12, height: 14)
    }

    // MARK: - Watching

    private var watchingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentAmber)
                Text(L10n.Projects.watchingTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                if session.activeWatch != nil {
                    Text(L10n.Projects.watchingActiveCount(1))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.99, green: 0.85, blue: 0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accentAmber.opacity(0.20)))
                }
                Spacer(minLength: 0)
                if session.activeWatch != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(accentEmerald)
                            .frame(width: 6, height: 6)
                        Text(L10n.Projects.watchingActiveLabel)
                            .font(.system(size: 10, weight: .semibold).monospaced())
                            .foregroundStyle(accentEmerald)
                    }
                }
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
            }

            if let watch = session.activeWatch {
                activeWatchBody(watch)
            } else if let ended = session.lastWatchEnded {
                endedWatchBody(ended)
            } else {
                emptyHint(L10n.Projects.watchingEmpty)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func activeWatchBody(_ watch: ProjectWatchTarget) -> some View {
        let port = liveItem(for: watch.pid)?.ports.first
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(watch.projectName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                        Text("/")
                            .foregroundStyle(.white.opacity(0.25))
                        Text(watch.label)
                            .font(.system(size: 11, weight: .bold).monospaced())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        if let port {
                            Text(":\(port)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
                            Text("·")
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        Text("PID \(watch.pid)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer(minLength: 4)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsedText(from: watch.startedAt, now: context.date))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    Button {
                        session.stopWatch(watch)
                    } label: {
                        Text(L10n.Projects.cancelWatch)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        session.openWatchLogs(for: watch)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "terminal")
                                .font(.system(size: 9, weight: .semibold))
                            Text(L10n.Projects.viewLog)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(watch.logPath == nil ? .white.opacity(0.35) : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(watch.logPath == nil ? Color.white.opacity(0.08) : accentBlue)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(watch.logPath == nil)
                    .help(watch.logPath == nil ? L10n.Projects.logNotFound : (watch.logPath ?? ""))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            Spacer(minLength: 0)
        }
    }

    private func endedWatchBody(_ ended: ProjectWatchEndedNotice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Projects.outcomeText(ended.outcome))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ended.outcome.isFailure ? Color(red: 1.0, green: 0.42, blue: 0.38) : .white)
            Text(L10n.Projects.watchingCommand(ended.label, ended.projectName))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
            let metaParts: [String] = [
                ended.durationSeconds > 0 ? L10n.Projects.durationText(ended.durationSeconds) : nil,
                ended.peakMemoryBytes > 0 ? L10n.Projects.memoryUsed(ended.peakMemoryBytes) : nil
            ].compactMap { $0 }
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button {
                    session.openEndedWatchLogs()
                } label: {
                    Text(L10n.Projects.viewLog)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ended.logPath == nil ? .white.opacity(0.35) : .white.opacity(0.90))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(ended.logPath == nil)
                Spacer(minLength: 0)
                Button {
                    session.dismissWatchEnded()
                } label: {
                    Text(L10n.Projects.watchEndedDismiss)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Containers

    private var containersCard: some View {
        let items = session.containerItems
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentCyan)
                Text(L10n.Projects.containersTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    containersToggleButton
                }
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
            }

            if items.isEmpty {
                emptyHint(L10n.Projects.containersEmpty)
                Spacer(minLength: 0)
            } else if containersExpanded {
                AlwaysVisibleScrollView(viewportFill: scrollViewportFill) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            expandedContainerRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(items.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(accentEmerald)
                                    .frame(width: 5, height: 5)
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            if let port = item.ports.first {
                                Text(":\(port)")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.40))
                            } else {
                                Text(" ")
                                    .font(.system(size: 9))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(rowFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                                )
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func expandedContainerRow(_ item: ProjectRuntimeItem) -> some View {
        let mem = item.memoryBytes > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(item.memoryBytes), countStyle: .memory)
            : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentEmerald)
                    .frame(width: 5, height: 5)
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !item.ports.isEmpty {
                    Text(L10n.Projects.containerPortBadge(item.ports))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(red: 0.45, green: 0.90, blue: 0.70))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(accentEmerald.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(accentEmerald.opacity(0.22), lineWidth: 1)
                                )
                        )
                }
                Spacer(minLength: 4)
                if let mem {
                    Text(L10n.Projects.containerResourceLine(item.cpuPercent, mem))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(1)
                } else if item.cpuPercent > 0 {
                    Text(String(format: "%.1f%%", item.cpuPercent))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.40))
                }
            }

            HStack(spacing: 6) {
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    AppLog.info("Projects", "点击重启容器", ["name": item.title])
                    session.restartContainer(item)
                } label: {
                    Text(L10n.Projects.containerRestart)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(item.containerID == nil)

                Button {
                    AppLog.info("Projects", "点击停止容器", ["name": item.title])
                    session.stopContainer(item)
                } label: {
                    Text(L10n.Projects.containerStop)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.97, green: 0.44, blue: 0.44))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .disabled(!item.canRelease || item.containerID == nil)
            }
            .padding(.top, 2)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 1)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var containersToggleButton: some View {
        Button {
            let next = !containersExpanded
            withAnimation(.easeInOut(duration: 0.2)) {
                containersExpanded = next
            }
            AppLog.info("Projects", "容器列表展开切换", [
                "expanded": next,
                "count": session.containerItems.count
            ])
        } label: {
            HStack(spacing: 2) {
                Text(containersExpanded ? L10n.Projects.hide : L10n.Projects.expandDetails)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: containersExpanded ? "chevron.down" : "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.45, green: 0.90, blue: 0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(accentCyan.opacity(0.12))
                    .overlay(Capsule().strokeBorder(accentCyan.opacity(0.22), lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(containersExpanded ? L10n.Projects.hide : L10n.Projects.expandDetails)
    }

    // MARK: - Shared

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.40))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func processMetaLine(_ item: ProjectRuntimeItem, memory: String) -> String {
        if let pid = item.pid {
            return L10n.Projects.processMeta(pid, item.cpuPercent, memory)
        }
        return L10n.Projects.resourceMemCPU(memory, String(format: "%.1f%%", item.cpuPercent))
    }

    private func liveItem(for pid: Int32) -> ProjectRuntimeItem? {
        session.groups.lazy
            .flatMap(\.items)
            .first { $0.pid == pid }
    }

    private func folderTint(for name: String) -> Color {
        let idx = abs(name.hashValue) % folderTints.count
        return folderTints[idx]
    }

    private func portForeground(_ port: Int) -> Color {
        switch port % 3 {
        case 0: return accentBlue
        case 1: return accentPink
        default: return accentPurple
        }
    }

    private func toggleCollapsed(_ id: String) {
        if collapsedProjectIDs.contains(id) {
            collapsedProjectIDs.remove(id)
        } else {
            collapsedProjectIDs.insert(id)
        }
        AppLog.debug("Projects", "工程树折叠切换", [
            "group": id,
            "collapsed": collapsedProjectIDs.contains(id)
        ])
    }

    private func elapsedText(from start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

private extension Color {
    static let zinc500 = Color(red: 0.445, green: 0.455, blue: 0.490)
}
