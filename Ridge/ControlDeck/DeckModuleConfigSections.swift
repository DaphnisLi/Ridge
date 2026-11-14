import AppKit
import SwiftUI

/// 货架模块预览配置（「已复制」提示已独立为 `builtin.copiedNotice`）。
struct ShelfWidgetConfigSection: View {
    @ObservedObject private var shelfSettings = ShelfSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    SettingsIslandPreviewCard(
                        widgetID: ControlDeckSettings.pageIDPrefix + ".shelf"
                    )
                    SettingsCard {
                        SettingsSwitchRow(
                            title: L10n.Shelf.magneticDropToggle,
                            subtitle: L10n.Shelf.magneticDropToggleSubtitle,
                            isOn: $shelfSettings.magneticDropCaptureEnabled
                        )
                    }
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                shelfSettings.restoreMagneticDropDefaults()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            AppLog.debug("ControlDeck", "货架配置预览已显示", [
                "magneticDrop": shelfSettings.magneticDropCaptureEnabled
            ])
        }
    }
}

/// 混音台模块预览配置。
struct VolumeWidgetConfigSection: View {
    @ObservedObject private var soundSettings = SoundSettings.shared
    @ObservedObject private var sound = SoundSession.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    // 未授权置顶；已授权整卡不展示。
                    SettingsPermissionCard(
                        status: sound.tapAvailability == .needsScreenCapture ? .request : .authorized,
                        symbol: "rectangle.dashed.badge.record",
                        tint: SettingsChrome.primary,
                        title: L10n.Sound.screenCaptureAccess,
                        subtitle: L10n.Sound.screenCaptureAccessDesc,
                        requestTitle: L10n.Sound.screenCaptureAllow,
                        requestSymbol: "rectangle.dashed.badge.record",
                        action: { sound.requestScreenCaptureAccess() }
                    )
                    SettingsIslandPreviewCard(
                        widgetID: ControlDeckSettings.pageIDPrefix + ".volume"
                    )
                    SettingsCard {
                        SettingsSwitchRow(
                            title: L10n.Sound.rememberVolumes,
                            subtitle: L10n.Sound.rememberVolumesSubtitle,
                            isOn: $soundSettings.rememberVolumes
                        )
                    }
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                soundSettings.restoreDefaults()
                sound.resetAppVolumes()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            sound.start()
            AppLog.debug("ControlDeck", "混音台配置预览已显示")
        }
    }
}

/// 项目释放模块预览配置（对齐「项目扫描目录」稿面）。
struct ProjectsWidgetConfigSection: View {
    @ObservedObject private var projectSettings = ProjectSettings.shared
    @ObservedObject private var session = ProjectReleaseSession.shared
    @State private var hoveredRoot: String?
    @State private var reindexNote: String?

    private var activeRootCount: Int {
        projectSettings.roots.reduce(0) { count, root in
            count + (Self.rootExists(root) ? 1 : 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
            previewChrome(moduleID: "projects")
            directoryCard
        }
        .onAppear {
            session.start()
            AppLog.debug("ControlDeck", "项目释放配置预览已显示", [
                "roots": projectSettings.roots.count,
                "active": activeRootCount
            ])
        }
    }

    private var directoryCard: some View {
        SettingsBentoCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(L10n.Projects.rootsTitle)
                            .font(SettingsChrome.Font.panelTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Projects.activeRootsBadge(activeRootCount))
                            .font(SettingsChrome.Font.chipSelected)
                            .foregroundStyle(SettingsChrome.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SettingsChrome.primary.opacity(0.10))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(SettingsChrome.primary.opacity(0.22), lineWidth: 1)
                                    )
                            )
                    }
                    Text(L10n.Projects.rootsIntro)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reindexNote, !reindexNote.isEmpty {
                        Text(reindexNote)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Button {
                        Task { await runReindex() }
                    } label: {
                        Label(
                            session.isRefreshing ? L10n.Projects.reindexRunning : L10n.Projects.reindexRoots,
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(SettingsChrome.Font.chipSelected)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(session.isRefreshing)

                    Button {
                        pickProjectRoot()
                    } label: {
                        Label(L10n.Projects.addRoot, systemImage: "plus")
                            .font(SettingsChrome.Font.chipSelected)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SettingsChrome.primary)
                    .controlSize(.small)
                }
            }

            SettingsHairline.flush

            rootsList
        }
    }

    @MainActor
    private func runReindex() async {
        reindexNote = L10n.Projects.reindexRunning
        let result = await session.reindexFromRuntime()
        reindexNote = L10n.Projects.reindexDone(
            added: result.addedRoots,
            roots: result.roots,
            projects: result.projects
        )
        AppLog.warn("Projects", "设置页重新索引已反馈", [
            "added": result.addedRoots,
            "roots": result.roots,
            "projects": result.projects
        ])
    }

    private var rootsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if projectSettings.roots.isEmpty {
                Text(L10n.Projects.rootsEmpty)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(12)
            } else {
                ForEach(Array(projectSettings.roots.enumerated()), id: \.element) { index, root in
                    rootRow(root)
                    if index < projectSettings.roots.count - 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.04))
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rootRow(_ root: String) -> some View {
        let stats = Self.stats(for: root, projects: session.projects, groups: session.groups)
        let hovering = hoveredRoot == root
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsChrome.primary.opacity(0.10))
                Image(systemName: "folder.fill")
                    .font(SettingsChrome.Font.iconTile)
                    .foregroundStyle(SettingsChrome.primary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(root)
                        .font(SettingsChrome.Font.monoEmphasis)
                        .foregroundStyle(hovering ? SettingsChrome.primary : SettingsChrome.onSurface)
                        .lineLimit(1)
                    if let badge = stats.badge {
                        Text(badge)
                            .font(SettingsChrome.Font.chip)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.black.opacity(0.05))
                            )
                    }
                }
                Text(stats.subtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button {
                    revealInFinder(root)
                } label: {
                    HStack(spacing: 2) {
                        Text(L10n.Projects.revealInFinder)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(hovering ? SettingsChrome.onSurface : SettingsChrome.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)

                Button {
                    projectSettings.removeRoot(root)
                    AppLog.info("Projects", "设置页移除项目根目录", ["root": root])
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(hovering ? SettingsChrome.error : SettingsChrome.onSurfaceVariant.opacity(0.65))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(hovering ? SettingsChrome.error.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.Projects.removeRootA11y)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(hovering ? SettingsChrome.cardBackground.opacity(0.85) : Color.clear)
        .onHover { isHovering in
            if isHovering {
                hoveredRoot = root
            } else if hoveredRoot == root {
                hoveredRoot = nil
            }
        }
    }

    private func pickProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.Projects.addRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectSettings.addRoot(url.path)
        AppLog.info("Projects", "设置页添加项目根目录")
    }

    private func revealInFinder(_ root: String) {
        let expanded = (root as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        AppLog.debug("Projects", "设置页在访达中定位根目录", ["root": root])
    }

    // MARK: - Root stats

    private struct RootStats {
        let subtitle: String
        let badge: String?
    }

    private static func rootExists(_ root: String) -> Bool {
        var isDir: ObjCBool = false
        let expanded = (root as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
    }

    private static func stats(
        for root: String,
        projects: [ScannedProject],
        groups: [ProjectRuntimeGroup]
    ) -> RootStats {
        let expanded = (root as NSString).expandingTildeInPath
        guard rootExists(root) else {
            return RootStats(subtitle: L10n.Projects.rootMissing, badge: nil)
        }
        let under = projects.filter { isUnderRoot($0.path, root: expanded) }
        let processCount = groups.reduce(0) { partial, group in
            guard let project = group.project, isUnderRoot(project.path, root: expanded) else {
                return partial
            }
            return partial + group.items.filter { $0.kind == .process }.count
        }
        let badge = kindBadge(for: under.map(\.kind))
        if under.isEmpty {
            return RootStats(subtitle: L10n.Projects.rootNoProjects, badge: badge)
        }
        if processCount > 0 {
            return RootStats(
                subtitle: L10n.Projects.rootDetectedWithRunning(under.count, processCount),
                badge: badge
            )
        }
        if let kindsLabel = kindSubtitleLabel(for: under.map(\.kind)) {
            return RootStats(
                subtitle: L10n.Projects.rootDetectedKinds(under.count, kindsLabel),
                badge: badge
            )
        }
        return RootStats(subtitle: L10n.Projects.rootDetected(under.count), badge: badge)
    }

    private static func isUnderRoot(_ path: String, root: String) -> Bool {
        let normalized = (path as NSString).standardizingPath.lowercased()
        let rootPath = (root as NSString).standardizingPath.lowercased()
        if normalized == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return normalized.hasPrefix(prefix)
    }

    private static func kindBadge(for kinds: [String]) -> String? {
        let set = Set(kinds)
        if !set.isEmpty, set.isSubset(of: ["xcode", "swift"]) {
            return L10n.Projects.kindXcode
        }
        return nil
    }

    private static func kindSubtitleLabel(for kinds: [String]) -> String? {
        let set = Set(kinds)
        guard !set.isEmpty else { return nil }
        if set.isSubset(of: ["xcode", "swift"]) {
            return L10n.Projects.kindXcode
        }
        if set.isSubset(of: ["node", "rust"]) || (set.contains("node") && set.contains("rust")) {
            return L10n.Projects.kindNodeRust
        }
        if set.count == 1, let only = set.first {
            switch only {
            case "node": return "Node"
            case "rust": return "Rust"
            case "go": return "Go"
            case "python": return "Python"
            case "java", "gradle": return "Java"
            default: return L10n.Projects.kindGenericRepos
            }
        }
        if set.count >= 3 {
            return L10n.Projects.kindGenericRepos
        }
        return nil
    }
}

// MARK: - Shared chrome

@MainActor
@ViewBuilder
private func previewChrome(moduleID: String) -> some View {
    SettingsIslandPreviewCard(widgetID: ControlDeckSettings.pageIDPrefix + "." + moduleID)
}
