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

    /// 内容型库顺序（可拖排序），不含控制台磁贴。
    private var contentLibraryOrder: [WidgetID] {
        settings.order.filter { registry.manifest(for: $0)?.showsInLibrary == true }
    }

    /// 已落地的控制台功能磁贴。
    private var liveDeckModules: [ControlDeckPlannedModule] {
        deckSettings.plannedModules.filter(\.isLive)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    let general = generalEntries
                    let developers = developerEntries
                    if general.isEmpty && developers.isEmpty {
                        Text(L10n.Widgets.libraryEmpty)
                            .font(SettingsChrome.Font.body)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                    } else {
                        if !general.isEmpty {
                            libraryGrid(entries: general)
                        }
                        if !developers.isEmpty {
                            Text(L10n.Widgets.developerSectionTitle)
                                .font(SettingsChrome.Font.sectionTitle)
                                .foregroundStyle(SettingsChrome.onSurface)
                                .padding(.top, general.isEmpty ? 0 : 8)
                                .accessibilityAddTraits(.isHeader)
                            libraryGrid(entries: developers)
                        }
                    }
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
                "general": generalEntries.count,
                "developer": developerEntries.count,
                "first": generalEntries.first?.id ?? developerEntries.first?.id ?? ""
            ])
        }
        .onChange(of: navigator.openToken) { _, _ in
            consumePendingPreviewIfNeeded()
        }
    }

    // MARK: - 库分段（通用 + 底部开发者）

    private enum LibraryEntry: Identifiable, Hashable {
        case deck(ControlDeckPlannedModule)
        case content(WidgetID)

        var id: WidgetID {
            switch self {
            case .deck(let module):
                return ControlDeckSettings.pageIDPrefix + "." + module.id
            case .content(let widgetID):
                return widgetID
            }
        }

        var isDeveloper: Bool {
            WidgetLibraryLayout.isDeveloperWidget(id)
        }
    }

    private var generalEntries: [LibraryEntry] {
        flatEntries.filter { !$0.isDeveloper }
    }

    private var developerEntries: [LibraryEntry] {
        flatEntries
            .filter(\.isDeveloper)
            .sorted {
                WidgetLibraryLayout.rank(of: $0.id) < WidgetLibraryLayout.rank(of: $1.id)
            }
    }

    /// 内容型按用户库序；控制台磁贴按扁平默认序插入固定槽位。
    private var flatEntries: [LibraryEntry] {
        var result: [LibraryEntry] = contentLibraryOrder.map { .content($0) }
        let decks = liveDeckModules.sorted {
            WidgetLibraryLayout.rank(of: ControlDeckSettings.pageIDPrefix + "." + $0.id)
                < WidgetLibraryLayout.rank(of: ControlDeckSettings.pageIDPrefix + "." + $1.id)
        }
        for module in decks {
            let pageID = ControlDeckSettings.pageIDPrefix + "." + module.id
            let index = insertionIndex(forDeckPageID: pageID, among: result)
            result.insert(.deck(module), at: index)
        }
        return result
    }

    @ViewBuilder
    private func libraryGrid(entries: [LibraryEntry]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SettingsChrome.Spacing.stack),
                GridItem(.flexible(), spacing: SettingsChrome.Spacing.stack)
            ],
            spacing: SettingsChrome.Spacing.stack
        ) {
            ForEach(entries) { entry in
                switch entry {
                case .deck(let module):
                    deckCardCell(module)
                case .content(let id):
                    if let manifest = registry.manifest(for: id) {
                        widgetCardCell(id: id, manifest: manifest)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.86),
            value: entries.map(\.id)
        )
    }

    private func insertionIndex(forDeckPageID pageID: WidgetID, among entries: [LibraryEntry]) -> Int {
        let deckRank = WidgetLibraryLayout.rank(of: pageID)
        for (index, entry) in entries.enumerated() {
            let entryRank: Int
            switch entry {
            case .content(let id):
                entryRank = WidgetLibraryLayout.rank(of: id)
            case .deck(let module):
                entryRank = WidgetLibraryLayout.rank(
                    of: ControlDeckSettings.pageIDPrefix + "." + module.id
                )
            }
            if entryRank > deckRank {
                return index
            }
        }
        return entries.count
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

    @ViewBuilder
    private func widgetCardCell(
        id: WidgetID,
        manifest: WidgetManifest
    ) -> some View {
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

/// 松手落在目标卡上时交换库顺序；开发者与通用分区互不跨拖。
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
        let dragDev = WidgetLibraryLayout.isDeveloperWidget(finishedID)
        let targetDev = WidgetLibraryLayout.isDeveloperWidget(targetID)
        guard dragDev == targetDev else {
            AppLog.debug("Settings", "拒绝跨分区拖拽小组件", [
                "id": finishedID,
                "with": targetID
            ])
            return false
        }
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

/// 库卡尺寸：提示 / 实况 / 面板同壳，灰舞台高度一律一致。
enum WidgetLibraryCardLayout {
    /// 灰舞台统一高（三族相同）。
    static let islandStageHeight: CGFloat = 106
    /// 整卡统一高（舞台 + 底栏 + 内边距）。
    static let cardHeight: CGFloat = 196

    // 兼容旧测试名 / 调用点。
    static var tipIslandStageHeight: CGFloat { islandStageHeight }
    static var tipCardHeight: CGFloat { cardHeight }
    static var contentIslandStageHeight: CGFloat { islandStageHeight }
    static var contentCardHeight: CGFloat { cardHeight }

    static func islandStageHeight(for family: WidgetLibraryFamily?) -> CGFloat {
        _ = family
        return islandStageHeight
    }

    static func cardHeight(for family: WidgetLibraryFamily?) -> CGFloat {
        _ = family
        return cardHeight
    }
}

private struct WidgetLibraryCard: View {
    let widgetID: WidgetID
    let title: String
    let summary: String
    /// 提示 / 实况 / 面板共用灰底居中舞台 + 底栏；灰舞台高度三族一致。
    var family: WidgetLibraryFamily? = nil
    @Binding var isEnabled: Bool
    var onOpen: () -> Void

    @ObservedObject private var colorPickSettings = ColorPickSettings.shared
    @ObservedObject private var ocrSelectSettings = OCRSelectSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                libraryIslandStage
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 8) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SettingsChrome.Font.sectionTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                            .lineLimit(1)
                        librarySummaryRow
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(SettingsChrome.Font.iconInline)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant.opacity(0.7))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Widgets.configureLink)
            }
        }
        .padding(SettingsChrome.Spacing.cardInner)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: WidgetLibraryCardLayout.cardHeight(for: family), alignment: .top)
        .background(SettingsChrome.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .opacity(isEnabled ? 1 : 0.72)
    }

    @ViewBuilder
    private var librarySummaryRow: some View {
        switch widgetID {
        case "builtin.colorPick":
            CaptureHotKeySummaryLabel(
                kind: .colorPick,
                chord: colorPickSettings.hotKey.displayString
            )
        case "builtin.ocrSelect":
            CaptureHotKeySummaryLabel(
                kind: .ocrSelect,
                chord: ocrSelectSettings.hotKey.displayString
            )
        default:
            Text(summary)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
        }
    }

    /// 灰舞台居中放黑岛（三族同壳）；黑岛统一缩到 290（「已复制」除外）。
    private var libraryIslandStage: some View {
        WidgetSamplePreview.island(for: widgetID, compact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 10)
            .frame(height: WidgetLibraryCardLayout.islandStageHeight(for: family))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SettingsChrome.outlineVariant.opacity(0.45), lineWidth: 1)
                    )
            )
            .clipped()
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
            || widgetID == "builtin.moveReminder"
            || widgetID == "builtin.worldClock"
            || widgetID == "builtin.stocks"
            || widgetID == "builtin.colorPick"
            || widgetID == "builtin.ocrSelect"
            || widgetID == "builtin.peripheralTip"
            || widgetID == "builtin.copiedNotice"
            || widgetID == ControlDeckSettings.pageIDPrefix + ".shelf"
            || widgetID == ControlDeckSettings.pageIDPrefix + ".volume"
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
        } else if widgetID == "builtin.moveReminder" {
            MoveReminderWidgetConfigSection()
        } else if widgetID == "builtin.worldClock" {
            WorldClockWidgetConfigSection()
        } else if widgetID == "builtin.stocks" {
            StockWidgetConfigSection()
        } else if widgetID == "builtin.colorPick" {
            ColorPickWidgetConfigSection()
        } else if widgetID == "builtin.ocrSelect" {
            OCRSelectWidgetConfigSection()
        } else if widgetID == "builtin.peripheralTip" {
            PeripheralTipWidgetConfigSection()
        } else if widgetID == "builtin.copiedNotice" {
            CopiedNoticeWidgetConfigSection()
        } else if widgetID == ControlDeckSettings.pageIDPrefix + ".shelf" {
            ShelfWidgetConfigSection()
        } else if widgetID == ControlDeckSettings.pageIDPrefix + ".volume" {
            VolumeWidgetConfigSection()
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

