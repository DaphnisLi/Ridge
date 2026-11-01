import SwiftUI

/// 控制台「项目释放」页：Running / Watching / Containers 三栏，对齐设计稿可读性。
struct ProjectReleaseDeckView: View {
    @ObservedObject private var session = ProjectReleaseSession.shared
    @State private var containersExpanded = false

    private let accent = Color(red: 0.678, green: 0.776, blue: 1.0)
    private let accentGreen = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let watchPurple = Color(red: 0.62, green: 0.48, blue: 0.98)
    private let containerBlue = Color(red: 0.40, green: 0.62, blue: 1.0)
    private let cardFill = Color.white.opacity(0.06)
    private let cardStroke = Color.white.opacity(0.08)
    /// 与卡片在黑底上的观感对齐的实心色，避免滚动裁切时透黑闪色。
    private let scrollViewportFill = Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 1))
    private let rowFill = Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1))

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 10
            let leftW = (geo.size.width - gap) * 0.52
            let rightW = geo.size.width - gap - leftW
            VStack(alignment: .leading, spacing: 6) {
                if let banner = session.lastActionBanner {
                    Text(banner)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accentGreen)
                        .lineLimit(1)
                }
                let rightH = max(0, geo.size.height - (session.lastActionBanner == nil ? 0 : 18))
                // 右侧两卡明确分高，避免监视中 / 容器互相抢高度叠在一起。
                let containerH = containersExpanded
                    ? rightH
                    : min(rightH, max(108, rightH * 0.38))
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
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Projects.deckTitle)
    }

    // MARK: - Running

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.Projects.runningTitle)
            if session.runningGroups.isEmpty {
                emptyHint(L10n.Projects.emptyState)
            } else {
                // 浮层 Panel 上系统 ScrollView 滚不动；用手动手势滚动，不画滚动条。
                AlwaysVisibleScrollView(viewportFill: scrollViewportFill) {
                    VStack(spacing: 8) {
                        ForEach(session.runningGroups) { group in
                            runningRow(group)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private func runningRow(_ group: ProjectRuntimeGroup) -> some View {
        let name = group.project?.name ?? L10n.Projects.unattributed
        let watching = session.isWatching(group: group)
        // 只展示真实进程；容器走右侧 Containers 卡，避免混进难读的代理进程。
        let processItems = group.items.filter { $0.kind == .process }
        let processCount = processItems.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(accentGreen.opacity(0.90))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accentGreen.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if processCount > 1 {
                            Text(L10n.Projects.processCount(processCount))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(accent.opacity(0.95))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(accent.opacity(0.16)))
                        }
                        if watching {
                            Circle()
                                .fill(watchPurple)
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text(resourceLine(group, processOnly: true))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if processItems.contains(where: { $0.pid != nil }) {
                    Button {
                        AppLog.info("Projects", "点击监视", ["project": name, "watching": !watching])
                        session.toggleWatchPrimary(in: group)
                    } label: {
                        Text(watching ? L10n.Projects.watchingActionOn : L10n.Projects.watchAction)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(watching ? watchPurple : .white.opacity(0.88))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(watching ? watchPurple.opacity(0.18) : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Projects.watchHelp)
                }

                if group.canRelease {
                    Button {
                        AppLog.info("Projects", "点击释放", ["project": name])
                        session.release(group: group)
                    } label: {
                        Text(session.isReleasing(group) ? L10n.Projects.releasing : L10n.Projects.release)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isReleasing(group))
                    .help(L10n.Projects.releaseHelp)
                }
            }

            // 每个进程一行：启动命令 + 端口（不展示 pid / 长路径 / 哈希）。
            ForEach(processItems.prefix(8)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.28))
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium).monospaced())
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let port = item.ports.first {
                        Text(":\(port)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.40))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 28)
            }
            if processCount > 6 {
                Text(L10n.Projects.moreItems(processCount - 6))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Watching

    private var watchingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(watchPurple)
                Text(L10n.Projects.watchingTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 0)
            }

            if let watch = session.activeWatch {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(from: watch.startedAt, now: context.date))
                        .font(.system(size: 28, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(L10n.Projects.watchingCommand(watch.label, watch.projectName))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)

                Text(L10n.Projects.watchingHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        session.openWatchLogs(for: watch)
                    } label: {
                        Text(L10n.Projects.openLog)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(watch.logPath == nil ? .white.opacity(0.35) : .white.opacity(0.90))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(watch.logPath == nil)
                    .help(watch.logPath == nil ? L10n.Projects.logNotFound : (watch.logPath ?? ""))

                    Spacer(minLength: 0)

                    Button {
                        session.stopWatch(watch)
                    } label: {
                        Text(L10n.Projects.stop)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            } else if let ended = session.lastWatchEnded {
                Text(L10n.Projects.outcomeText(ended.outcome))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ended.outcome.isFailure ? Color(red: 1.0, green: 0.42, blue: 0.38) : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                        Text(L10n.Projects.openLog)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ended.logPath == nil ? .white.opacity(0.35) : .white.opacity(0.90))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                emptyHint(L10n.Projects.watchingEmpty)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    // MARK: - Containers

    private var containersCard: some View {
        let items = session.containerItems
        let totalMem = items.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(containerBlue)
                Text(L10n.Projects.containersTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 0)
                // 「查看 / 收起」固定在容器卡片右上角。
                if !items.isEmpty {
                    containersToggleButton
                }
            }

            if items.isEmpty {
                emptyHint(L10n.Projects.containersEmpty)
                Spacer(minLength: 0)
            } else if containersExpanded {
                Text(containersSummary(count: items.count, memory: totalMem))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                AlwaysVisibleScrollView(viewportFill: scrollViewportFill) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items.prefix(12)) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if !item.detail.isEmpty {
                                    Text("\(L10n.Projects.imageLabel) \(item.detail)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.45))
                                        .lineLimit(1)
                                }
                                if !item.ports.isEmpty {
                                    Text(L10n.Projects.ports(item.ports))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.45))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(rowFill)
                            )
                            // 与货架/粘贴板相同：扁平化后再裁切，避免半透明边缘闪色。
                            .compositingGroup()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(containersSummary(count: items.count, memory: totalMem))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if let first = items.first {
                    Text(first.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
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
            Text(containersExpanded ? L10n.Projects.hide : L10n.Projects.show)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(containersExpanded ? L10n.Projects.hide : L10n.Projects.show)
    }

    // MARK: - Shared

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.40))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func resourceLine(_ group: ProjectRuntimeGroup, processOnly: Bool = false) -> String {
        let items = processOnly ? group.items.filter { $0.kind == .process } : group.items
        let memBytes = items.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let cpu = items.reduce(0.0) { $0 + $1.cpuPercent }
        let mem = ByteCountFormatter.string(fromByteCount: Int64(memBytes), countStyle: .memory)
        let cpuText = String(format: "%.0f%%", cpu)
        let ports = Set(items.flatMap(\.ports)).sorted()
        if ports.isEmpty {
            return L10n.Projects.resourceMemCPU(mem, cpuText)
        }
        let portText = L10n.Projects.ports(Array(ports.prefix(3)))
        return L10n.Projects.resourceMemCPUPorts(mem, cpuText, portText)
    }

    private func containersSummary(count: Int, memory: UInt64) -> String {
        if memory > 0 {
            let mem = ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)
            return L10n.Projects.containersSummary(count, mem)
        }
        return L10n.Projects.containersCountOnly(count)
    }

    private func elapsedText(from start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
