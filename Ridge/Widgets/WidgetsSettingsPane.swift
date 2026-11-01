import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetsSettingsPane: View {
    @ObservedObject var settings: WidgetSettings
    @ObservedObject private var navigator = SettingsNavigator.shared
    private let registry = WidgetRegistry.shared

    @State private var path = NavigationPath()
    @State private var draggingID: WidgetID?

    private var libraryOrder: [WidgetID] {
        settings.order.filter { registry.manifest(for: $0)?.showsInLibrary == true }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.Widgets.libraryIntro)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    librarySection
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
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
            AppLog.debug("Settings", "小组件库页已显示", ["count": libraryOrder.count])
        }
        .onChange(of: navigator.openToken) { _, _ in
            consumePendingPreviewIfNeeded()
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
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Widgets.libraryTitle)
                .font(.system(size: 15, weight: .semibold))

            if libraryOrder.isEmpty {
                Text(L10n.Widgets.libraryEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
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
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: id) {
                WidgetLibraryCard(
                    manifest: manifest,
                    isEnabled: settings.isEnabled(id)
                )
            }
            .buttonStyle(.plain)
            .opacity(draggingID == id ? 0.35 : 1)

            Toggle(
                "",
                isOn: Binding(
                    get: { settings.isEnabled(id) },
                    set: { enabled in
                        handleEnableChange(id: id, enabled: enabled)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(10)
        }
        .background(
            WidgetCardScreenFrameReader(widgetID: id)
        )
        .onDrag {
            draggingID = id
            AppLog.debug("Settings", "开始拖拽小组件卡", ["id": id])
            return NSItemProvider(object: id as NSString)
        } preview: {
            WidgetLibraryCard(
                manifest: manifest,
                isEnabled: settings.isEnabled(id)
            )
            .frame(width: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        nsView.reportIfNeeded()
    }

    final class ReaderView: NSView {
        var widgetID: WidgetID = ""

        override func layout() {
            super.layout()
            reportIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportIfNeeded()
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
    let manifest: WidgetManifest
    let isEnabled: Bool
    @ObservedObject private var islandSettings = IslandSettings.shared

    private var palette: IslandPalette { islandSettings.theme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.84, blue: 0.90),
                        Color(red: 0.90, green: 0.92, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 列表卡片只用静态样张，避免每次 body 重建 IslandWidget 实例。
                WidgetIslandPreviewChrome(
                    manifest: manifest,
                    palette: palette,
                    compact: true
                )
                .padding(.horizontal, 16)
            }
            .frame(height: 120)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(manifest.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(manifest.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(SettingsChrome.surfaceContainerLow.opacity(0.55))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .opacity(isEnabled ? 1 : 0.72)
    }
}

// MARK: - 预览页

private struct WidgetPreviewPane: View {
    let widgetID: WidgetID
    @ObservedObject private var islandSettings = IslandSettings.shared
    private let registry = WidgetRegistry.shared

    private var manifest: WidgetManifest? {
        registry.manifest(for: widgetID)
    }

    private var previewWidth: CGFloat {
        min(CGFloat(islandSettings.expandedWidth), 420)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let manifest {
                    if widgetID == "builtin.meeting" {
                        // 会议页自带岛预览与配置，不再套通用灰底预览。
                        MeetingWidgetConfigSection()
                    } else if widgetID == "builtin.media" {
                        MediaWidgetConfigSection()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color(red: 0.78, green: 0.84, blue: 0.90),
                                    Color(red: 0.92, green: 0.94, blue: 0.96)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            LiveWidgetIslandPreview(
                                widgetID: widgetID,
                                palette: islandSettings.theme.palette,
                                width: previewWidth,
                                height: 96,
                                bottomRadius: CGFloat(islandSettings.bottomCornerRadius)
                            )
                            .padding(.horizontal, 28)
                        }

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
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(SettingsChrome.pageBackground)
        .navigationTitle(
            widgetID == "builtin.meeting"
                ? L10n.Widgets.meetingPreviewTitle
                : widgetID == "builtin.media"
                    ? L10n.Widgets.mediaPreviewTitle
                    : (manifest?.displayName ?? L10n.Common.preview)
        )
        .onAppear {
            AppLog.info("Settings", "打开小组件预览", ["id": widgetID])
        }
    }
}

// MARK: - 静态 / 实况岛预览

private struct WidgetIslandPreviewChrome: View {
    let manifest: WidgetManifest
    let palette: IslandPalette
    var compact: Bool

    private var previewHeight: CGFloat { compact ? 44 : 72 }
    private var bottomRadius: CGFloat { compact ? 14 : 20 }

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: bottomRadius)
        HStack(spacing: 10) {
            Image(systemName: WidgetLibraryStyle.symbol(for: manifest.id))
                .font(.system(size: compact ? 14 : 18, weight: .semibold))
                .foregroundStyle(palette.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(manifest.displayName)
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                if !compact {
                    Text(manifest.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .frame(maxWidth: .infinity)
        .frame(height: previewHeight)
        .background(shape.fill(palette.fill))
        .clipShape(shape)
        .environment(\.islandPalette, palette)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

private struct LiveWidgetIslandPreview: View {
    let widgetID: WidgetID
    let palette: IslandPalette
    let width: CGFloat
    let height: CGFloat
    let bottomRadius: CGFloat

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: min(bottomRadius, height / 2, width / 2))
        Group {
            if let view = WidgetPreviewFactory.makeView(for: widgetID) {
                view
                    .padding(.horizontal, 12)
            } else {
                Text(L10n.Widgets.cannotPreview)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(width: width, height: height)
        .background(shape.fill(palette.fill))
        .clipShape(shape)
        .environment(\.islandPalette, palette)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
    }
}

// MARK: - 样式辅助

private enum WidgetLibraryStyle {
    static func symbol(for id: WidgetID) -> String {
        switch id {
        case "builtin.meeting": return "calendar"
        case "builtin.media": return "music.note.list"
        default: return "rectangle.3.group"
        }
    }
}
