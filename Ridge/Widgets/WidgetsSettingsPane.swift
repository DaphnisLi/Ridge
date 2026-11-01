import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetsSettingsPane: View {
    @ObservedObject var settings: WidgetSettings
    private let registry = WidgetRegistry.shared

    @State private var path = NavigationPath()
    @State private var draggingID: WidgetID?

    private var libraryOrder: [WidgetID] {
        settings.order.filter { registry.manifest(for: $0)?.showsInLibrary == true }
    }

    private var hasActiveComboPage: Bool {
        settings.comboPages.indices.contains(settings.activeComboPageIndex)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("打开开关后可在灵动岛展示。先新建组合页，再点卡片上的加号放入（每页最多 8 格，未满也按一行四格排布）。拖到另一张卡片可交换库顺序。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    comboPagesSection

                    librarySection
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

    // MARK: - 组合页

    private var comboPagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("组合页")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    _ = settings.createComboPage()
                    AppLog.info("Settings", "用户新建组合页", [
                        "index": settings.activeComboPageIndex
                    ])
                } label: {
                    Label("新建组合页", systemImage: "plus.rectangle.on.rectangle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if settings.comboPages.isEmpty {
                Text("还没有组合页。新建后，点小组件卡片左下角加号即可放入。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(settings.comboPages.indices), id: \.self) { index in
                    comboPageRow(index: index)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
        )
    }

    @ViewBuilder
    private func comboPageRow(index: Int) -> some View {
        let members = settings.comboPages[index]
        let selected = settings.activeComboPageIndex == index
        let cellUsed = members.reduce(0) { $0 + settings.gridSize(for: $1).cellCount }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    settings.activeComboPageIndex = index
                    WidgetRuntime.shared.focusComboPage(at: index)
                    AppLog.debug("Settings", "选中组合页", ["index": index])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                        Text("组合页 \(index + 1)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("\(members.count) 个 · \(cellUsed)/8 格")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    settings.deleteComboPage(at: index)
                    WidgetRuntime.shared.recompute(reason: "comboDelete")
                    AppLog.info("Settings", "删除组合页", ["index": index])
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("删除组合页")
            }

            if members.isEmpty {
                Text("空页 · 点下方卡片加号加入")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                FlowMemberChips(
                    ids: members,
                    name: { registry.manifest(for: $0)?.displayName ?? $0 },
                    onRemove: { id in
                        _ = settings.removeWidgetFromComboPage(id)
                        WidgetRuntime.shared.recompute(reason: "comboRemove")
                        IslandController.shared?.beginSettingsSession()
                        AppLog.info("Settings", "移出组合页", ["id": id, "page": index])
                    }
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - 库

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("小组件库")
                .font(.system(size: 15, weight: .semibold))

            if libraryOrder.isEmpty {
                Text("暂无可用小组件。")
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
        let inCombo = settings.comboPageIndex(containing: id)
        let canAdd = hasActiveComboPage && inCombo != settings.activeComboPageIndex

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

            // 左下角：加入 / 移出当前组合页
            VStack {
                Spacer(minLength: 0)
                HStack {
                    comboActionButton(id: id, inCombo: inCombo, canAdd: canAdd)
                    Spacer(minLength: 0)
                }
                .padding(10)
            }
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

    @ViewBuilder
    private func comboActionButton(id: WidgetID, inCombo: Int?, canAdd: Bool) -> some View {
        if let inCombo, inCombo == settings.activeComboPageIndex {
            Button {
                _ = settings.removeWidgetFromComboPage(id)
                WidgetRuntime.shared.recompute(reason: "comboRemove")
                IslandController.shared?.beginSettingsSession()
                AppLog.info("Settings", "从当前组合页移除", ["id": id])
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("从当前组合页移除")
        } else if canAdd {
            Button {
                addToActiveCombo(id)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("加入当前组合页")
            .disabled(!settings.isEnabled(id))
            .opacity(settings.isEnabled(id) ? 1 : 0.35)
        } else if !hasActiveComboPage {
            EmptyView()
        } else if let inCombo {
            Text("组合页 \(inCombo + 1)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    private func addToActiveCombo(_ id: WidgetID) {
        guard settings.isEnabled(id) else {
            AppLog.warn("Settings", "未启用，无法加入组合页", ["id": id])
            return
        }
        let page = settings.activeComboPageIndex
        guard settings.addWidgetToComboPage(id, pageIndex: page) else { return }
        WidgetRuntime.shared.focusComboPage(at: page)
        IslandController.shared?.beginSettingsSession()
        AppLog.info("Settings", "加号加入组合页", ["id": id, "page": page])
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

/// 组合页成员小标签。
private struct FlowMemberChips: View {
    let ids: [WidgetID]
    let name: (WidgetID) -> String
    let onRemove: (WidgetID) -> Void

    var body: some View {
        FlexibleChipWrap(ids: ids, name: name, onRemove: onRemove)
    }
}

private struct FlexibleChipWrap: View {
    let ids: [WidgetID]
    let name: (WidgetID) -> String
    let onRemove: (WidgetID) -> Void

    var body: some View {
        // 简单横排换行：用 LazyVGrid 自适应小芯片。
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: 4) {
                    Text(name(id))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Button {
                        onRemove(id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
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
