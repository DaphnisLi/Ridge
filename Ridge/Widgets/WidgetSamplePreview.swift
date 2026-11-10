import AppKit
import SwiftUI

// MARK: - 统一岛预览舞台（灰底 + 可选多形态 Tab）

/// 设置页岛预览的一种形态；多于 1 个时才显示上方选择题。
struct SettingsIslandStageOption: Identifiable, Hashable {
    let id: String
    var title: String
    var badge: String
    var symbol: String
    var tint: Color
    /// 岛最大宽度；`nil` 表示不设上限。
    var maxIslandWidth: CGFloat? = nil
    /// `true`：黑岛贴合内容宽（展开态）；`false`：拉到 `maxIslandWidth` / 舞台宽（待命等）。
    var hugsContent: Bool = false
    var bottomRadius: CGFloat = 26
    /// 岛预览外形：上直角下圆角（与真岛一致）。
    var outlineStyle: IslandOutlineStyle = .panel
    var minStageHeight: CGFloat = 148
    /// 传给 `WidgetIslandPreviewShell`：紧凑样张去掉重阴影。
    var compactShell: Bool = false
}

/// 设置页统一岛预览舞台：灰底仿真台 + 黑岛；多形态时显示选择题，仅一种时隐藏。
struct SettingsIslandStage<Content: View>: View {
    var title: String? = nil
    var options: [SettingsIslandStageOption]
    @Binding var selection: String
    @ViewBuilder var content: (SettingsIslandStageOption) -> Content

    private var selectedOption: SettingsIslandStageOption {
        options.first(where: { $0.id == selection }) ?? options[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title, !title.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(SettingsChrome.secondary)
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Spacer(minLength: 0)
                }
            }

            if options.count > 1 {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: min(options.count, 5)
                    ),
                    spacing: 8
                ) {
                    ForEach(options) { option in
                        stageTab(option)
                    }
                }
            }

            stageCanvas
        }
        .padding(SettingsChrome.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private var stageCanvas: some View {
        let option = selectedOption
        let island = WidgetIslandPreviewShell(
            compact: option.compactShell,
            bottomRadius: option.bottomRadius,
            outlineStyle: option.outlineStyle,
            hugsContent: option.hugsContent
        ) {
            content(option)
        }
        .frame(maxWidth: option.maxIslandWidth)

        return Group {
            if option.hugsContent {
                // 贴顶贴合内容：矮 tip 若垂直居中会在舞台里上下空一大截，看起来边距乱。
                island
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: option.minStageHeight, alignment: .top)
            } else {
                island
                    .frame(maxWidth: .infinity, minHeight: option.minStageHeight, alignment: .top)
            }
        }
        .allowsHitTesting(false)
    }

    private func stageTab(_ option: SettingsIslandStageOption) -> some View {
        let selected = selection == option.id
        return Button {
            selection = option.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(option.tint)
                Text(option.title)
                    .font(SettingsChrome.Font.chip)
                    .foregroundStyle(selected ? SettingsChrome.onSurface : SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(option.badge)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(selected ? option.tint : SettingsChrome.outline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? SettingsChrome.cardBackground : SettingsChrome.surfaceContainer)
                    .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 3, y: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension SettingsIslandStage {
    /// 单形态便捷：不展示选择题。
    init(
        title: String? = nil,
        compact: Bool = false,
        maxIslandWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let option = SettingsIslandStageOption(
            id: "default",
            title: "",
            badge: "",
            symbol: "",
            tint: .clear,
            maxIslandWidth: maxIslandWidth,
            hugsContent: false,
            bottomRadius: compact ? 16 : 26,
            minStageHeight: compact ? 120 : 148,
            compactShell: compact
        )
        self.title = title
        self.options = [option]
        self._selection = .constant(option.id)
        self.content = { _ in content() }
    }
}

/// 设置页「岛预览」外包：灰底舞台 + 假数据岛（单形态，无选择题）。
struct SettingsIslandPreviewCard: View {
    let widgetID: WidgetID
    var compact: Bool = false
    var title: String? = nil

    var body: some View {
        SettingsIslandStage(title: title, compact: compact) {
            WidgetSamplePreview.content(for: widgetID, compact: compact)
        }
    }
}

/// 设置页岛预览壳：上直角、下圆角。新预览请调 `WidgetSamplePreview.island` / `SettingsIslandStage`。
struct WidgetIslandPreviewShell<Content: View>: View {
    var compact: Bool = false
    var bottomRadius: CGFloat? = nil
    var outlineStyle: IslandOutlineStyle = .panel
    /// `true` 时黑岛随内容固有宽度，不横向拉满。
    var hugsContent: Bool = false
    @ViewBuilder var content: () -> Content

    private var radius: CGFloat {
        bottomRadius ?? (compact ? 16 : 26)
    }

    var body: some View {
        let shape = IslandOutlineShape(style: outlineStyle, bottomRadius: radius)
        // 库卡 compact：去掉阴影，滚动时少做一层离屏模糊合成。
        Group {
            if hugsContent {
                content()
                    .fixedSize(horizontal: true, vertical: true)
            } else {
                content()
                    .frame(maxWidth: .infinity)
            }
        }
        .background(
            shape
                // 与真岛不透明漆黑一致；半透明黑在库卡白底上会发灰（短 tip 尤甚）。
                .fill(Color.black)
                .overlay(
                    shape.stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(
                    color: compact ? .clear : .black.opacity(0.28),
                    radius: compact ? 0 : 18,
                    y: compact ? 0 : 8
                )
        )
        .clipShape(shape)
    }
}

/// 设置页小组件预览的**唯一入口**（假数据）。库卡 `compact: true`，详情页 `compact: false`。
/// 新 widget：在 `content(for:compact:)` 加 case，调用方只调 `island(for:compact:)`。
@MainActor
enum WidgetSamplePreview {
    /// 统一预览组件：壳 + 假数据内容。
    @ViewBuilder
    static func island(for id: WidgetID, compact: Bool) -> some View {
        WidgetIslandPreviewShell(
            compact: compact,
            outlineStyle: outlineStyle(for: id),
            hugsContent: hugsIslandContent(for: id)
        ) {
            content(for: id, compact: compact)
        }
    }

    /// 库卡 / 详情预览：一律上直角下圆角（与真岛一致）。
    private static func outlineStyle(for _: WidgetID) -> IslandOutlineStyle { .panel }

    /// 窄内容（股票两卡 / 瞬时引导等）贴合固有宽，避免黑岛被库卡舞台横向拉满。
    private static func hugsIslandContent(for id: WidgetID) -> Bool {
        switch id {
        case "builtin.stocks",
             "builtin.colorPick",
             "builtin.ocrSelect",
             "builtin.aiUsage",
             "builtin.moveReminder",
             "builtin.focusTimer",
             "builtin.meeting":
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    static func content(for id: WidgetID, compact: Bool) -> some View {
        switch id {
        case "builtin.meeting":
            meetingSample(compact: compact)
        case "builtin.media":
            mediaSample(compact: compact)
        case "builtin.focusTimer":
            focusTimerSample(compact: compact)
        case "builtin.aiUsage":
            aiUsageSample(compact: compact)
        case "builtin.moveReminder":
            moveReminderSample(compact: compact)
        case "builtin.worldClock":
            worldClockSample(compact: compact)
        case "builtin.stocks":
            stocksSample(compact: compact)
        case "builtin.colorPick":
            colorPickSample(compact: compact)
        case "builtin.ocrSelect":
            ocrSelectSample(compact: compact)
        case "system.controlDeck.battery":
            batterySample(compact: compact)
        case "system.controlDeck.volume":
            volumeSample(compact: compact)
        case "system.controlDeck.projects":
            projectsSample(compact: compact)
        case "system.controlDeck.shelf":
            shelfSample(compact: compact)
        default:
            genericSample(
                title: WidgetRegistry.shared.manifest(for: id)?.displayName ?? id,
                symbol: "rectangle.3.group",
                compact: compact
            )
        }
    }

    private static func meetingSample(compact: Bool) -> some View {
        MeetingIslandCardView.previewSample(urgency: .relaxed, compact: true)
            .padding(.horizontal, IslandChrome.contentHorizontal)
            .padding(.bottom, IslandChrome.compactTipBottom)
            .frame(minHeight: compact ? 30 : 34)
    }

    private static func mediaSample(compact: Bool) -> some View {
        MediaIslandCardView.previewSample()
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 10 : 14)
            .frame(maxWidth: compact ? .infinity : 540)
            .frame(minHeight: compact ? 96 : 160)
    }

    private static func focusTimerSample(compact: Bool) -> some View {
        FocusTimerIslandCardView.previewSample(phase: .running, compact: compact)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: compact ? .infinity : 540)
            .frame(minHeight: compact ? 44 : 72)
    }

    private static func aiUsageSample(compact: Bool) -> some View {
        // 与会议 tip 同款翼布局；预览壳无真 IslandChrome，只补左右/底。
        AIUsageIslandCardView.previewSample(stage: .warning, compact: true)
            .padding(.horizontal, IslandChrome.contentHorizontal)
            .padding(.bottom, IslandChrome.compactTipBottom)
            .frame(minHeight: compact ? 30 : 34)
    }

    private static func moveReminderSample(compact: Bool) -> some View {
        let settings = MoveReminderSettings.shared
        // 与会议 tip 同款翼布局预览边距。
        return MoveReminderNoticeCard.previewSample(
            activeMinutes: settings.activeTriggerMinutes,
            restMinutes: settings.suggestedRestMinutes,
            compact: true
        )
        .padding(.horizontal, IslandChrome.contentHorizontal)
        .padding(.bottom, IslandChrome.compactTipBottom)
        .frame(minHeight: compact ? 30 : 34)
    }

    private static func worldClockSample(compact: Bool) -> some View {
        WorldClockIslandView.previewSample()
            .padding(.horizontal, compact ? 10 : IslandChrome.contentHorizontal)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: compact ? .infinity : 560)
    }

    private static func colorPickSample(compact: Bool) -> some View {
        // 与久坐 tip 同款：黑岛贴合内容，舞台只补左右/底。
        ColorPickTipIslandView(compact: true)
            .padding(.horizontal, IslandChrome.contentHorizontal)
            .padding(.bottom, IslandChrome.compactTipBottom)
            .frame(minHeight: compact ? 30 : 34)
    }

    private static func ocrSelectSample(compact: Bool) -> some View {
        OCRSelectTipIslandView(compact: true)
            .padding(.horizontal, IslandChrome.contentHorizontal)
            .padding(.bottom, IslandChrome.compactTipBottom)
            .frame(minHeight: compact ? 30 : 34)
    }

    private static func stocksSample(compact: Bool) -> some View {
        // 两卡紧凑样张：单卡约 128（价签不截断）；纵向贴合内容，勿拉高。
        StockIslandView.previewSample(compact: true)
            .padding(.horizontal, compact ? 8 : IslandChrome.contentHorizontal)
            .padding(.vertical, compact ? 8 : 10)
            .fixedSize(horizontal: true, vertical: true)
    }

    private static func batterySample(compact: Bool) -> some View {
        BatteryDeckView(previewDevices: BatteryDeckView.sampleDevices)
            .frame(height: compact ? 148 : 210)
            .padding(.horizontal, compact ? 6 : 0)
            .padding(.vertical, compact ? 8 : 12)
    }

    private static func volumeSample(compact: Bool) -> some View {
        DeckVolumePreviewSample(compact: compact)
            .frame(height: compact ? 168 : 230)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 10 : 14)
    }

    private static func projectsSample(compact: Bool) -> some View {
        DeckProjectsPreviewSample(compact: compact)
            .frame(height: compact ? 168 : 230)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 10 : 14)
    }

    private static func shelfSample(compact: Bool) -> some View {
        DeckShelfPreviewSample(compact: compact)
            .frame(height: compact ? 168 : 230)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 10 : 14)
    }

    private static func genericSample(title: String, symbol: String, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .frame(height: compact ? 44 : 56)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 控制台磁贴假数据样张（对齐真岛布局，库卡 / 详情共用）

private struct DeckPreviewPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

private struct DeckShelfPreviewSample: View {
    var compact: Bool

    private let accentBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let accentPurple = Color(red: 0.545, green: 0.361, blue: 0.965)

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 10) {
            // 左栏对齐真岛空货架：投放提示，不用假文件条目。
            DeckPreviewPanel {
                VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                    header(symbol: "shippingbox.fill", tint: accentBlue, title: L10n.Shelf.shelfTitle)
                    ShelfDropStagingView(highlighted: false, fillsContainer: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            DeckPreviewPanel {
                VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                    clipboardHeader
                    clipRow(symbol: "doc.text", tint: .orange, text: L10n.Shelf.previewClipText, time: L10n.Shelf.previewClipTimeRecent)
                    clipRow(symbol: "link", tint: accentBlue, text: L10n.Shelf.previewClipLink, time: L10n.Shelf.previewClipTimeMid)
                    if !compact {
                        clipRow(symbol: "paintpalette.fill", tint: accentPurple, text: L10n.Shelf.previewClipColor, time: L10n.Shelf.previewClipTimeOlder)
                    }
                }
            }
        }
    }

    private var clipboardHeader: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accentPurple.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(accentPurple.opacity(0.30), lineWidth: 1)
                    )
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(accentPurple)
            }
            .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)

            Text(L10n.Shelf.clipboardTitle)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            clipboardSearchField
                .frame(minWidth: compact ? 72 : 120, maxWidth: .infinity)
        }
    }

    /// 假数据搜索框（不可编辑），对齐真岛剪贴板顶栏。
    private var clipboardSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.40))
            Text(L10n.Shelf.clipboardSearchPlaceholder)
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 4 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func header(symbol: String, tint: Color, title: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                    )
                Image(systemName: symbol)
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
            Text(title)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func clipRow(symbol: String, tint: Color, text: String, time: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(text)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(time)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

private struct DeckVolumePreviewSample: View {
    var compact: Bool

    private let accent = Color(red: 0.678, green: 0.776, blue: 1.0)
    private let accentGreen = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let blueMid = Color(red: 0.510, green: 0.659, blue: 1.0)

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 10) {
            DeckPreviewPanel {
                VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: compact ? 10 : 11))
                                .foregroundStyle(accent)
                            Text(L10n.Sound.masterOutputVolume)
                                .font(.system(size: compact ? 10 : 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("62%")
                            .font(.system(size: compact ? 11 : 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }

                    volumeTrack(fill: 0.62, colors: [
                        Color(red: 0.23, green: 0.51, blue: 1.0),
                        blueMid,
                        accent
                    ])

                    Text(L10n.Sound.currentOutputDevice)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.40))
                        .textCase(.uppercase)
                        .padding(.top, 2)

                    deviceCard(
                        symbol: "laptopcomputer",
                        name: L10n.Sound.previewDeviceSpeakers,
                        selected: true
                    )
                    deviceCard(
                        symbol: "headphones",
                        name: L10n.Sound.previewDeviceAirPods,
                        selected: false,
                        battery: 78
                    )
                }
            }

            DeckPreviewPanel {
                VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: compact ? 10 : 11))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(L10n.Sound.perAppMix)
                                .font(.system(size: compact ? 10 : 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(L10n.Sound.activeSources(2))
                            .font(.system(size: 9, weight: .medium).monospaced())
                            .foregroundStyle(accentGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(accentGreen.opacity(0.12))
                            )
                    }

                    appRow(name: L10n.Sound.previewAppMusic, volume: 0.72, playing: true)
                    appRow(name: L10n.Sound.previewAppSafari, volume: 0.40, playing: false)
                }
            }
        }
    }

    private func volumeTrack(fill: CGFloat, colors: [Color]) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * fill, 8))
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, min(geo.size.width - 10, geo.size.width * fill - 5)))
            }
        }
        .frame(height: 10)
    }

    private func deviceCard(symbol: String, name: String, selected: Bool, battery: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? accentGreen : .white.opacity(0.55))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: compact ? 10 : 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(0.72))
                    .lineLimit(1)
                if selected {
                    Text(L10n.Sound.activeOutput)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            Spacer(minLength: 0)
            if let battery {
                Text("\(battery)%")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            } else if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accentGreen)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.white.opacity(0.09) : Color.clear)
        )
    }

    private func appRow(name: String, volume: CGFloat, playing: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.7))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Text(playing ? L10n.Sound.appPlaying : L10n.Sound.appIdle)
                    .font(.system(size: 8).monospaced())
                    .foregroundStyle(.white.opacity(0.40))
            }
            .frame(width: compact ? 44 : 56, alignment: .leading)

            volumeTrack(fill: volume, colors: [accent.opacity(0.85), accent])
                .frame(maxWidth: .infinity)

            Text("\(Int((volume * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct DeckProjectsPreviewSample: View {
    var compact: Bool

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    private let accentCyan = Color(red: 0.024, green: 0.714, blue: 0.831)
    private let accentAmber = Color(red: 0.961, green: 0.620, blue: 0.043)
    private let accentEmerald = Color(red: 0.204, green: 0.827, blue: 0.600)

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 10) {
            DeckPreviewPanel {
                runningPreview
            }

            VStack(spacing: compact ? 6 : 8) {
                DeckPreviewPanel {
                    VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                                .foregroundStyle(accentAmber)
                            Text(L10n.Projects.watchingTitle)
                                .font(.system(size: compact ? 10 : 11, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            HStack(spacing: 3) {
                                Circle().fill(accentEmerald).frame(width: 5, height: 5)
                                Text(L10n.Projects.watchingActiveLabel)
                                    .font(.system(size: 8, weight: .semibold).monospaced())
                                    .foregroundStyle(accentEmerald)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(L10n.Projects.previewProjectName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.45))
                                Text("/")
                                    .foregroundStyle(.white.opacity(0.25))
                                Text(L10n.Projects.previewCommandBuild)
                                    .font(.system(size: 10, weight: .bold).monospaced())
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            HStack {
                                Text("PID 18422")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.45))
                                Spacer(minLength: 0)
                                Text("12:08")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                    }
                }

                DeckPreviewPanel {
                    VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                                .foregroundStyle(accentCyan)
                            Text(L10n.Projects.containersTitle)
                                .font(.system(size: compact ? 10 : 11, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 6) {
                            containerChip(L10n.Projects.previewContainerDB, port: 5432)
                            containerChip(L10n.Projects.previewContainerCache, port: 6379)
                        }
                    }
                }
            }
        }
    }

    /// 对齐真岛「运行中进程」：顶栏 + 工程折叠行 + 树形命令行（监视 / 释放）。
    private var runningPreview: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 5) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Text(L10n.Projects.runningTitle)
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Circle()
                        .fill(accentEmerald)
                        .frame(width: 5, height: 5)
                    Text(L10n.Projects.treeStreamLabel)
                        .font(.system(size: 8, weight: .medium).monospaced())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 10)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accentAmber)
                    Text(L10n.Projects.previewProjectName)
                        .font(.system(size: compact ? 11 : 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(L10n.Projects.commandCount(2))
                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)))
                    Spacer(minLength: 4)
                    Text(L10n.Projects.projectCPU(17.5))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                    Text("412 MB")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )

                VStack(spacing: 4) {
                    processRow(
                        title: L10n.Projects.previewCommandBuild,
                        port: nil,
                        meta: L10n.Projects.processMeta(18422, 12.4, "286 MB"),
                        watching: true
                    )
                    processRow(
                        title: L10n.Projects.previewCommandDev,
                        port: 5173,
                        meta: L10n.Projects.processMeta(19001, 5.1, "126 MB"),
                        watching: false
                    )
                }
                .padding(.leading, 14)
            }
        }
    }

    private func processRow(title: String, port: Int?, meta: String, watching: Bool) -> some View {
        HStack(spacing: 5) {
            treeBranchMark
            Circle()
                .fill(watching ? accentBlue : accentEmerald)
                .frame(width: 5, height: 5)
                .overlay {
                    if watching {
                        Circle()
                            .fill(accentBlue.opacity(0.55))
                            .frame(width: 5, height: 5)
                            .scaleEffect(1.6)
                            .opacity(0.5)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: compact ? 10 : 11, weight: watching ? .bold : .semibold).monospaced())
                        .foregroundStyle(watching ? Color(red: 0.75, green: 0.85, blue: 1.0) : .white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let port {
                        Text(":\(port)")
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color(red: 0.925, green: 0.282, blue: 0.600))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 0.925, green: 0.282, blue: 0.600).opacity(0.18))
                            )
                    }
                }
                Text(meta)
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(watching ? accentBlue.opacity(0.75) : .white.opacity(0.40))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if watching {
                HStack(spacing: 2) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(L10n.Projects.watchingActionOn)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(accentBlue))
            } else {
                Text(L10n.Projects.watchAction)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.10)))
            }

            Text(L10n.Projects.release)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(red: 0.97, green: 0.44, blue: 0.44))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.red.opacity(0.10)))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(watching ? accentBlue.opacity(0.10) : Color.black.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            watching ? accentBlue.opacity(0.30) : Color.white.opacity(0.04),
                            lineWidth: 1
                        )
                )
        )
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

    private func containerChip(_ title: String, port: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Circle().fill(accentEmerald).frame(width: 4, height: 4)
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text(":\(port)")
                .font(.system(size: 8).monospacedDigit())
                .foregroundStyle(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }
}
