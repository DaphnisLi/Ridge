import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetsSettingsPane: View {
    @ObservedObject var settings: WidgetSettings
    private let registry = WidgetRegistry.shared

    @State private var path = NavigationPath()
    /// 正在拖的卡片；整卡跟随指针，松手落在另一张上时交换。
    @State private var draggingID: WidgetID?
    @State private var dragPointer: CGPoint = .zero
    @State private var dragCardSize: CGSize = .zero
    @State private var dropTargetID: WidgetID?

    private var libraryOrder: [WidgetID] {
        settings.order.filter { registry.manifest(for: $0)?.showsInLibrary == true }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("打开开关后可在灵动岛展示；拖到另一张卡片上可交换顺序。点击卡片进入预览。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if libraryOrder.isEmpty {
                        Text("暂无可用小组件。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    } else {
                        ZStack(alignment: .topLeading) {
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

                            if let draggingID,
                               let manifest = registry.manifest(for: draggingID) {
                                floatingDragCard(manifest: manifest, id: draggingID)
                            }
                        }
                        .coordinateSpace(name: WidgetCardLayoutCache.spaceName)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .background(SettingsChrome.pageBackground)
            .navigationDestination(for: WidgetID.self) { id in
                WidgetPreviewPane(widgetID: id)
            }
        }
        .onAppear {
            settings.reconcile(with: registry)
            IslandController.shared?.beginSettingsSession()
            AppLog.debug("Settings", "小组件库页已显示", ["count": libraryOrder.count])
        }
    }

    @ViewBuilder
    private func floatingDragCard(manifest: WidgetManifest, id: WidgetID) -> some View {
        WidgetLibraryCard(
            manifest: manifest,
            isEnabled: settings.isEnabled(id)
        )
        .frame(width: dragCardSize.width, height: max(dragCardSize.height, 1))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        .position(dragPointer)
        .allowsHitTesting(false)
        .zIndex(100)
    }

    @ViewBuilder
    private func widgetCardCell(id: WidgetID, manifest: WidgetManifest) -> some View {
        let isDragging = draggingID == id
        let isDropTarget = dropTargetID == id && draggingID != nil && draggingID != id

        ZStack(alignment: .topTrailing) {
            WidgetLibraryCard(
                manifest: manifest,
                isEnabled: settings.isEnabled(id)
            )
            .opacity(isDragging ? 0.2 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDropTarget ? Color.accentColor.opacity(0.85) : Color.clear,
                        lineWidth: 2
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                guard draggingID == nil else { return }
                path.append(id)
            }
            .gesture(cardDragGesture(id: id))

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
            .opacity(isDragging ? 0.2 : 1)
            .allowsHitTesting(!isDragging)
        }
        .background(
            WidgetCardScreenFrameReader(widgetID: id)
        )
        .background(
            WidgetCardLocalFrameReader(widgetID: id)
        )
    }

    private func cardDragGesture(id: WidgetID) -> some Gesture {
        DragGesture(
            minimumDistance: 8,
            coordinateSpace: .named(WidgetCardLayoutCache.spaceName)
        )
        .onChanged { value in
            if draggingID == nil {
                draggingID = id
                if let frame = WidgetCardLayoutCache.shared.frame(for: id) {
                    dragCardSize = frame.size
                    dragPointer = CGPoint(x: frame.midX, y: frame.midY)
                } else {
                    dragCardSize = CGSize(width: 220, height: 210)
                    dragPointer = value.location
                }
                AppLog.debug("Settings", "开始拖拽小组件卡", ["id": id])
            }
            dragPointer = value.location
            dropTargetID = hitTestDropTarget(at: value.location, excluding: id)
        }
        .onEnded { value in
            let finishedID = draggingID
            let targetID = hitTestDropTarget(at: value.location, excluding: finishedID)
            draggingID = nil
            dropTargetID = nil
            dragPointer = .zero
            dragCardSize = .zero

            guard let finishedID, let targetID, finishedID != targetID else {
                AppLog.debug("Settings", "拖拽取消或未落在其它卡上", [
                    "id": finishedID ?? "",
                    "target": targetID ?? ""
                ])
                return
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
        }
    }

    private func hitTestDropTarget(at point: CGPoint, excluding: WidgetID?) -> WidgetID? {
        for id in libraryOrder where id != excluding {
            guard let frame = WidgetCardLayoutCache.shared.frame(for: id) else { continue }
            if frame.contains(point) {
                return id
            }
        }
        return nil
    }

    private func handleEnableChange(id: WidgetID, enabled: Bool) {
        settings.setEnabled(id, enabled: enabled)
        if enabled {
            let source = WidgetCardFrameCache.shared.frame(for: id)
            IslandController.shared?.presentWidgetEnabled(id, fromScreenRect: source)
        } else {
            IslandController.shared?.beginSettingsSession()
            WidgetRuntime.shared.recompute(reason: "settingsDisable")
            AppLog.info("Settings", "关闭小组件展示", ["id": id])
        }
    }
}

// MARK: - 本地坐标（拖拽命中用，不写 @State）

@MainActor
final class WidgetCardLayoutCache {
    static let shared = WidgetCardLayoutCache()
    static let spaceName = "widgetLibrary"

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

    func remove(_ id: WidgetID) {
        frames[id] = nil
    }
}

private struct WidgetCardLocalFrameReader: View {
    let widgetID: WidgetID

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    WidgetCardLayoutCache.shared.set(
                        widgetID,
                        geo.frame(in: .named(WidgetCardLayoutCache.spaceName))
                    )
                }
                .onChange(of: geo.frame(in: .named(WidgetCardLayoutCache.spaceName))) { _, newFrame in
                    WidgetCardLayoutCache.shared.set(widgetID, newFrame)
                }
        }
    }
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

                Label(
                    WidgetLibraryStyle.category(for: manifest.source),
                    systemImage: WidgetLibraryStyle.symbol(for: manifest.id)
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.orange.opacity(0.9))
                .lineLimit(1)

                Text(manifest.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(SettingsChrome.cardBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        Label(
                            WidgetLibraryStyle.category(for: manifest.source),
                            systemImage: WidgetLibraryStyle.symbol(for: manifest.id)
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        Text(manifest.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("找不到该小组件。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SettingsChrome.pageBackground)
        .navigationTitle(manifest?.displayName ?? "预览")
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
                Text("无法预览")
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
        case "builtin.media": return "music.note"
        case "builtin.meeting": return "calendar"
        case "builtin.status": return "battery.100"
        default: return "rectangle.3.group"
        }
    }

    static func category(for source: WidgetSource) -> String {
        switch source {
        case .builtin: return "内置"
        case .user: return "自定义"
        case .generated: return "AI"
        }
    }
}
