import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetsSettingsPane: View {
    @ObservedObject var settings: WidgetSettings
    @ObservedObject private var deckSettings = ControlDeckSettings.shared
    @ObservedObject private var navigator = SettingsNavigator.shared
    private let registry = WidgetRegistry.shared

    @State private var path = NavigationPath()
    @State private var draggingID: WidgetID?

    private var libraryOrder: [WidgetID] {
        settings.order.filter { registry.manifest(for: $0)?.showsInLibrary == true }
    }

    /// 已落地的控制台功能磁贴（进小组件库，样式同卡片）。
    private var liveDeckModules: [ControlDeckPlannedModule] {
        deckSettings.plannedModules.filter(\.isLive)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.pageHorizontal) {
                    deckLibrarySection
                    librarySection
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.vertical, SettingsChrome.Spacing.pageHorizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .background(SettingsChrome.pageBackground)
            .navigationDestination(for: WidgetID.self) { id in
                WidgetPreviewPane(widgetID: id)
            }
        }
        .onAppear {
            settings.reconcile(with: registry)
            // 小组件设计页用页内预览，真岛保持收起。
            IslandController.shared?.beginSettingsSessionCollapsed()
            consumePendingPreviewIfNeeded()
            AppLog.debug("Settings", "小组件库页已显示", [
                "widgets": libraryOrder.count,
                "deck": liveDeckModules.count
            ])
        }
        .onChange(of: navigator.openToken) { _, _ in
            consumePendingPreviewIfNeeded()
        }
    }

    private var deckLibrarySection: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
            librarySectionHeader(
                symbol: "square.grid.2x2",
                symbolTint: SettingsChrome.primary,
                title: L10n.Widgets.deckSectionTitle,
                badge: "\(L10n.Widgets.deckSectionBadge) (\(liveDeckModules.count))",
                aside: L10n.Widgets.deckSectionAside
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SettingsChrome.Spacing.stack),
                    GridItem(.flexible(), spacing: SettingsChrome.Spacing.stack)
                ],
                spacing: SettingsChrome.Spacing.stack
            ) {
                ForEach(liveDeckModules) { module in
                    deckCardCell(module)
                }
            }
        }
    }

    @ViewBuilder
    private func deckCardCell(_ module: ControlDeckPlannedModule) -> some View {
        let pageID = ControlDeckSettings.pageIDPrefix + "." + module.id
        WidgetLibraryCard(
            widgetID: pageID,
            title: module.title,
            summary: deckSummary(for: module.id),
            isEnabled: Binding(
                get: { deckSettings.isModuleEnabled(module.id) },
                set: { enabled in
                    handleDeckEnableChange(id: module.id, enabled: enabled)
                }
            ),
            onOpen: { path.append(pageID) }
        )
        .background(WidgetCardScreenFrameReader(widgetID: pageID))
    }

    private func librarySectionHeader(
        symbol: String,
        symbolTint: Color,
        title: String,
        badge: String,
        aside: String
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(SettingsChrome.Font.iconTile)
                    .foregroundStyle(symbolTint)
                Text(title)
                    .font(SettingsChrome.Font.sectionTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(badge)
                    .font(SettingsChrome.Font.chip)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
            }
            Spacer(minLength: 8)
            Text(aside)
                .font(SettingsChrome.Font.chip)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .multilineTextAlignment(.trailing)
        }
    }

    private func deckSummary(for id: String) -> String {
        switch id {
        case "battery": return L10n.ControlDeck.moduleBatterySummary
        case "volume": return L10n.ControlDeck.moduleVolumeSummaryLive
        case "projects": return L10n.Projects.widgetSummary
        case "shelf": return L10n.ControlDeck.moduleShelfSummary
        default: return ""
        }
    }

    private func handleDeckEnableChange(id: String, enabled: Bool) {
        deckSettings.setModuleEnabled(id, enabled)
        if enabled {
            let pageID = ControlDeckSettings.pageIDPrefix + "." + id
            // 滚动后 layout 不再持续上报，开关前再采一次。
            WidgetCardFrameCache.shared.refreshFromWindows()
            let source = WidgetCardFrameCache.shared.frame(for: pageID)
            if let pane = ControlDeckSettings.Pane(rawValue: id) {
                WidgetRuntime.shared.focusControlDeck(pane: pane)
            }
            IslandController.shared?.presentWidgetEnabled(pageID, fromScreenRect: source)
            AppLog.info("Settings", "打开功能磁贴，同步上岛", ["id": id])
        } else {
            IslandController.shared?.beginSettingsSessionCollapsed()
            WidgetRuntime.shared.recompute(reason: "deckModuleDisable")
            AppLog.info("Settings", "关闭功能磁贴，同步下岛", ["id": id])
        }
    }

    private func consumePendingPreviewIfNeeded() {
        guard let id = navigator.consumePendingWidgetPreview() else { return }
        path = NavigationPath()
        path.append(id)
        AppLog.info("Settings", "已跳转小组件预览", ["id": id])
    }

    // MARK: - 库

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
            librarySectionHeader(
                symbol: "rectangle.stack",
                symbolTint: SettingsChrome.primary,
                title: L10n.Widgets.contentSectionTitle,
                badge: "\(L10n.Widgets.contentSectionBadge) (\(libraryOrder.count))",
                aside: L10n.Widgets.contentSectionAside
            )

            if libraryOrder.isEmpty {
                Text(L10n.Widgets.libraryEmpty)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: SettingsChrome.Spacing.stack),
                        GridItem(.flexible(), spacing: SettingsChrome.Spacing.stack)
                    ],
                    spacing: SettingsChrome.Spacing.stack
                ) {
                    ForEach(libraryOrder, id: \.self) { id in
                        if let manifest = registry.manifest(for: id) {
                            widgetCardCell(id: id, manifest: manifest)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                }
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.86),
                    value: libraryOrder
                )
            }
        }
    }

    @ViewBuilder
    private func widgetCardCell(id: WidgetID, manifest: WidgetManifest) -> some View {
        WidgetLibraryCard(
            widgetID: id,
            title: manifest.displayName,
            summary: manifest.summary,
            isEnabled: Binding(
                get: { settings.isEnabled(id) },
                set: { enabled in
                    handleEnableChange(id: id, enabled: enabled)
                }
            ),
            onOpen: { path.append(id) }
        )
        .opacity(draggingID == id ? 0.35 : 1)
        .background(WidgetCardScreenFrameReader(widgetID: id))
        .onDrag {
            draggingID = id
            AppLog.debug("Settings", "开始拖拽小组件卡", ["id": id])
            return NSItemProvider(object: id as NSString)
        } preview: {
            WidgetLibraryCard(
                widgetID: id,
                title: manifest.displayName,
                summary: manifest.summary,
                isEnabled: .constant(settings.isEnabled(id)),
                onOpen: {}
            )
            .frame(width: 260)
            .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        }
        .onDrop(
            of: [.text, .plainText, .utf8PlainText],
            delegate: WidgetCardReorderDropDelegate(
                targetID: id,
                draggingID: $draggingID,
                settings: settings
            )
        )
    }

    private func handleEnableChange(id: WidgetID, enabled: Bool) {
        settings.setEnabled(id, enabled: enabled)
        if enabled {
            WidgetCardFrameCache.shared.refreshFromWindows()
            let source = WidgetCardFrameCache.shared.frame(for: id)
            IslandController.shared?.presentWidgetEnabled(id, fromScreenRect: source)
            AppLog.info("Settings", "打开小组件，同步上岛", ["id": id])
        } else {
            WidgetRuntime.shared.withdrawDisplay(id)
            // 仍在小组件设计页，保持「不钉住预览」，避免关掉开关后岛被钉死不收。
            IslandController.shared?.beginSettingsSessionCollapsed()
            WidgetRuntime.shared.recompute(reason: "settingsDisable")
            AppLog.info("Settings", "关闭小组件，同步下岛", ["id": id])
        }
    }
}

/// 松手落在目标卡上时交换库顺序。
private struct WidgetCardReorderDropDelegate: DropDelegate {
    let targetID: WidgetID
    @Binding var draggingID: WidgetID?
    let settings: WidgetSettings

    func dropEntered(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let finishedID = draggingID
        draggingID = nil
        guard let finishedID, finishedID != targetID else { return false }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            _ = settings.move(draggedID: finishedID, onto: targetID)
        }
        DispatchQueue.main.async {
            IslandController.shared?.presentWidgetReordered(finishedID)
            AppLog.info("Settings", "拖拽交换完成", [
                "id": finishedID,
                "with": targetID
            ])
        }
        return true
    }

    func dropExited(info: DropInfo) {}
}

// MARK: - 屏幕坐标（不写 @State，避免 layout ↔ 刷新死循环）

@MainActor
final class WidgetCardFrameCache {
    static let shared = WidgetCardFrameCache()
    private var frames: [WidgetID: CGRect] = [:]
    private var reporters: [WidgetID: () -> Void] = [:]

    func set(_ id: WidgetID, _ rect: CGRect) {
        if let old = frames[id],
           abs(old.midX - rect.midX) < 1,
           abs(old.midY - rect.midY) < 1,
           abs(old.width - rect.width) < 1,
           abs(old.height - rect.height) < 1 {
            return
        }
        frames[id] = rect
    }

    func frame(for id: WidgetID) -> CGRect? {
        frames[id]
    }

    func register(_ id: WidgetID, reporter: @escaping () -> Void) {
        reporters[id] = reporter
    }

    func unregister(_ id: WidgetID) {
        reporters.removeValue(forKey: id)
    }

    /// 开关飞入前主动刷新可见卡的屏幕矩形。
    func refreshFromWindows() {
        for report in reporters.values {
            report()
        }
    }
}

private struct WidgetCardScreenFrameReader: NSViewRepresentable {
    let widgetID: WidgetID

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.widgetID = widgetID
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.widgetID = widgetID
        WidgetCardFrameCache.shared.register(widgetID) { [weak nsView] in
            nsView?.reportIfNeeded()
        }
    }

    static func dismantleNSView(_ nsView: ReaderView, coordinator: ()) {
        WidgetCardFrameCache.shared.unregister(nsView.widgetID)
    }

    final class ReaderView: NSView {
        var widgetID: WidgetID = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // 不在 layout 里刷坐标：滚动时 layout 极频，转换屏幕矩形会拖卡。
            WidgetCardFrameCache.shared.register(widgetID) { [weak self] in
                self?.reportIfNeeded()
            }
            DispatchQueue.main.async { [weak self] in
                self?.reportIfNeeded()
            }
        }

        func reportIfNeeded() {
            guard !widgetID.isEmpty,
                  let window,
                  bounds.width > 1,
                  bounds.height > 1
            else { return }
            let windowRect = convert(bounds, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            WidgetCardFrameCache.shared.set(widgetID, screenRect)
        }
    }
}

// MARK: - 库卡片

private struct WidgetLibraryCard: View {
    let widgetID: WidgetID
    let title: String
    let summary: String
    @Binding var isEnabled: Bool
    var onOpen: () -> Void

    /// 全库统一卡面尺寸：岛区贴顶、信息区贴底，中间留白。
    private enum CardLayout {
        static let islandStageHeight: CGFloat = 176
        static let cardHeight: CGFloat = 340
    }

    private var category: String { L10n.Widgets.categoryBadge(for: widgetID) }
    private var footerHint: String { L10n.Widgets.cardFooterHint(for: widgetID) }
    private var footerSymbol: String { L10n.Widgets.cardFooterSymbol(for: widgetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 黑岛样张内容不变；固定舞台高度，矮岛也贴顶。
            Button(action: onOpen) {
                WidgetSamplePreview.island(for: widgetID, compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .drawingGroup(opaque: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: CardLayout.islandStageHeight, alignment: .top)
            .clipped()

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Button(action: onOpen) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(SettingsChrome.Font.sectionTitle)
                                .foregroundStyle(SettingsChrome.onSurface)
                                .lineLimit(1)
                            Text(category)
                                .font(SettingsChrome.Font.chip)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(SettingsChrome.surfaceContainer)
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Button(action: onOpen) {
                    Text(summary)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    HStack(alignment: .center, spacing: 8) {
                        Label {
                            Text(footerHint)
                                .font(SettingsChrome.Font.chip)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: footerSymbol)
                                .font(SettingsChrome.Font.iconInline)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        }
                        .labelStyle(.titleAndIcon)

                        Spacer(minLength: 8)

                        HStack(spacing: 2) {
                            Text(L10n.Widgets.configureLink)
                                .font(SettingsChrome.Font.label)
                            Image(systemName: "arrow.up.right")
                                .font(SettingsChrome.Font.iconInline)
                        }
                        .foregroundStyle(SettingsChrome.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SettingsChrome.Spacing.cardInner)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CardLayout.cardHeight, alignment: .top)
        .background(SettingsChrome.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .opacity(isEnabled ? 1 : 0.72)
    }
}

// MARK: - 预览页

private struct WidgetPreviewPane: View {
    let widgetID: WidgetID
    private let registry = WidgetRegistry.shared

    private var deckPane: ControlDeckSettings.Pane? {
        ControlDeckSettings.Pane.from(pageID: widgetID)
    }

    private var manifest: WidgetManifest? {
        registry.manifest(for: widgetID)
    }

    private var navigationTitleText: String {
        if let deckPane {
            return deckPane.title
        }
        if widgetID == "builtin.meeting" { return L10n.Widgets.meetingPreviewTitle }
        if widgetID == "builtin.media" { return L10n.Widgets.mediaPreviewTitle }
        if widgetID == "builtin.focusTimer" { return L10n.Widgets.focusTimerPreviewTitle }
        return manifest?.displayName ?? L10n.Common.preview
    }

    /// 自带 ScrollView + 贴底「恢复默认」栏的配置页，外层不再包一层滚动。
    private var ownsPinnedRestoreFooter: Bool {
        widgetID == "builtin.meeting"
            || widgetID == "builtin.focusTimer"
            || widgetID == "builtin.aiUsage"
    }

    var body: some View {
        Group {
            if ownsPinnedRestoreFooter {
                pinnedRestoreConfigBody
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        scrollableConfigBody
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(SettingsChrome.pageBackground)
        .navigationTitle(navigationTitleText)
        .onAppear {
            AppLog.info("Settings", "打开小组件预览", ["id": widgetID])
        }
    }

    @ViewBuilder
    private var pinnedRestoreConfigBody: some View {
        if widgetID == "builtin.meeting" {
            MeetingWidgetConfigSection()
        } else if widgetID == "builtin.focusTimer" {
            FocusTimerWidgetConfigSection()
        } else if widgetID == "builtin.aiUsage" {
            AIUsageWidgetConfigSection()
        }
    }

    @ViewBuilder
    private var scrollableConfigBody: some View {
        if let deckPane {
            deckConfig(for: deckPane)
        } else if let manifest {
            if widgetID == "builtin.media" {
                MediaWidgetConfigSection()
            } else {
                SettingsIslandPreviewCard(widgetID: widgetID)

                VStack(alignment: .leading, spacing: 8) {
                    Text(manifest.displayName)
                        .font(.system(size: 22, weight: .semibold))
                    Text(manifest.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(L10n.Widgets.notFound)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func deckConfig(for pane: ControlDeckSettings.Pane) -> some View {
        switch pane {
        case .battery:
            BatteryWidgetConfigSection()
        case .volume:
            VolumeWidgetConfigSection()
        case .projects:
            ProjectsWidgetConfigSection()
        case .shelf:
            ShelfWidgetConfigSection()
        }
    }
}

