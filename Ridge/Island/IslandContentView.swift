import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandContentView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @ObservedObject var runtime: WidgetRuntime
    @ObservedObject private var controlDeck = ControlDeckSettings.shared
    @ObservedObject private var shelfDropSession = ShelfDropSession.shared
    @ObservedObject private var shelfSettings = ShelfSettings.shared
    @ObservedObject private var focusTimer = FocusTimerSession.shared
    @ObservedObject private var nowPlaying = NowPlayingService.shared
    @ObservedObject private var widgetSettings = WidgetSettings.shared
    @ObservedObject private var noticeCenter = IslandNoticeCenter.shared
    @State private var shelfDropTargeted = false

    private var shelfDropEnabled: Bool {
        controlDeck.isModuleEnabled("shelf")
    }

    /// 整岛双舱（暂存 / 隔空传送）仅在货架开且磁吸拖放开时出现。
    private var shelfMagneticStagingActive: Bool {
        shelfDropEnabled
            && shelfSettings.magneticDropCaptureEnabled
            && shelfDropSession.isActive
    }

    /// 播放中常驻小岛（番茄优先占用左右翼；大面板仅点按后出现）。
    private var showsMediaCompactStandby: Bool {
        MediaCompactPresence.isActive
    }

    private var compactSize: CGSize {
        // 高度一律等于刘海：贴顶时底边齐平，禁止 max(…, 38) 再抬高掉出刘海。
        let height = NotchGeometry.compactPanelHeight(notchHeight: viewModel.notchHeight)
        // 番茄计时中：收起态加宽，左右翼展示待命倒计时（对齐 Live Activity）。
        if focusTimer.showsCompactStandby {
            return CGSize(
                width: NotchGeometry.pixelAlign(
                    max(viewModel.notchWidth * NotchGeometry.compactScale, NotchGeometry.focusTimerCompactWidth)
                ),
                height: height
            )
        }
        if showsMediaCompactStandby {
            return CGSize(
                width: NotchGeometry.pixelAlign(
                    max(viewModel.notchWidth * NotchGeometry.compactScale, NotchGeometry.mediaCompactWidth)
                ),
                height: height
            )
        }
        return CGSize(
            width: NotchGeometry.pixelAlign(viewModel.notchWidth * NotchGeometry.compactScale),
            height: height
        )
    }

    /// 货架拖入暂存态固定控制台画布（切掉 IslandBody 后无 Preference）。
    private var shelfDropPanelSize: CGSize {
        CGSize(
            width: NotchGeometry.controlDeckPreferredWidth,
            height: NotchGeometry.controlDeckMinHeight
        )
    }

    /// 可见面板尺寸：收起用刘海/待命；展开用内容测量结果（viewModel.panelSize）。
    private var bodySize: CGSize {
        if viewModel.isExpanded {
            if shelfMagneticStagingActive {
                return shelfDropPanelSize
            }
            let measured = viewModel.panelSize
            if measured.width > 1, measured.height > 1 {
                return measured
            }
            return compactSize
        }
        return compactSize
    }

    /// 「已复制」等：刘海右侧正圆微岛；其余贴顶直角下圆角。
    private var outlineStyle: IslandOutlineStyle {
        usesNotchRightOrb ? .circle : .panel
    }

    private var usesNotchRightOrb: Bool {
        runtime.isTransientNoticePage
            && (noticeCenter.current?.usesNotchRightOrbChrome == true)
    }

    private var appliedBottomRadius: CGFloat {
        if usesNotchRightOrb {
            return IslandChrome.notchRightOrbDiameter / 2
        }
        // 控制台混音台稿面底部约 26pt 圆角。
        let preferred = runtime.isControlDeckPage
            ? max(CGFloat(settings.bottomCornerRadius), 26)
            : CGFloat(settings.bottomCornerRadius)
        return min(
            preferred,
            bodySize.height / 2,
            bodySize.width / 2
        )
    }

    /// 圆岛相对刘海中心右偏（与 `IslandController` 可点区一致）。
    private var panelHorizontalOffset: CGFloat {
        guard usesNotchRightOrb else { return 0 }
        return IslandChrome.notchRightOrbCenterOffsetX(notchWidth: viewModel.notchWidth)
    }

    private var palette: IslandPalette { settings.theme.palette }

    var body: some View {
        let shape = IslandOutlineShape(style: outlineStyle, bottomRadius: appliedBottomRadius)
        return ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // AppKit device 色不透明层：比 SwiftUI Color 经透明窗合成更接近刘海漆黑。
                // 圆岛改由内容自绘 SwiftUI 黑底——NSView fill 易盖住 Ø32 内的 SF Symbol。
                if !usesNotchRightOrb {
                    IslandOpaqueFillView(
                        bottomRadius: appliedBottomRadius,
                        outlineStyle: outlineStyle,
                        fill: settings.theme.nsFillColor
                    )
                    .frame(width: bodySize.width, height: bodySize.height)
                }

                if viewModel.isExpanded, shelfMagneticStagingActive {
                    // 磁吸拖放：整岛切成双舱（暂存 / 隔空传送）；关闭磁吸后不进此态。
                    // 必须自报控制台画布尺寸——切掉 IslandBody 后 Preference 会停在刘海，吸住又立刻收。
                    ShelfDropStagingView(highlighted: true, fillsIsland: true)
                        .padding(.horizontal, IslandChrome.contentHorizontal)
                        .padding(.top, max(28, viewModel.notchHeight + 4))
                        .padding(.bottom, IslandChrome.contentBottom)
                        .frame(width: shelfDropPanelSize.width, height: shelfDropPanelSize.height)
                        .reportIslandPanelSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    IslandBody(
                        isExpanded: viewModel.isExpanded,
                        notchHeight: viewModel.notchHeight,
                        runtime: runtime
                    )
                    // 按内容固有尺寸布局，再上报给 ViewModel；勿先铺满面板。
                    .fixedSize(horizontal: true, vertical: true)
                    .reportIslandPanelSize()
                    // 圆岛内容压过 AppKit OpaqueFill，避免只见黑底不见图标。
                    .zIndex(usesNotchRightOrb ? 2 : 0)
                }
            }
            // 面板框跟已测尺寸走；内容用 fixedSize 自撑，避免矮框 clip 把新页热区裁掉。
            .frame(width: bodySize.width, height: bodySize.height, alignment: .top)
            .animation(.easeOut(duration: 0.18), value: shelfDropSession.isActive)
            .clipShape(shape)
            // 整块面板都要可命中，避免透明子区把点击漏给下层页面。
            .contentShape(shape)
            // 圆岛：先裁圆再右偏，避免 clip 吃掉偏移后的可视区。
            .offset(x: panelHorizontalOffset)
            // 货架开启时：整岛接收文件拖入（不限货架小栏）。
            .onDrop(of: [.fileURL], isTargeted: $shelfDropTargeted) { providers in
                guard shelfDropEnabled else { return false }
                // 整岛拖入态由左右舱各自 onDrop 承接；外层只负责磁吸命中与兜底暂存。
                if shelfDropSession.isActive {
                    AppLog.debug("Shelf", "整岛兜底暂存（未命中左右舱）", [
                        "providers": providers.count
                    ])
                } else {
                    AppLog.info("Shelf", "整岛接收拖入", [
                        "providers": providers.count,
                        "expanded": viewModel.isExpanded,
                        "page": runtime.activeID ?? "nil"
                    ])
                }
                return ShelfClipboardDeckView.ingestDrop(providers: providers, into: ShelfStore.shared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.islandPalette, palette)
        .environment(\.islandNotchHeight, viewModel.notchHeight)
        .environment(\.islandNotchWidth, viewModel.notchWidth)
        .animation(islandSpring, value: viewModel.appearance)
        .animation(islandSpring, value: runtime.contentEpoch)
        .animation(islandSpring, value: settings.bottomCornerRadius)
        .animation(islandSpring, value: settings.theme)
        .animation(islandSpring, value: viewModel.panelSize)
        .animation(islandSpring, value: focusTimer.showsCompactStandby)
        .animation(islandSpring, value: focusTimer.snapshot.remainingSeconds)
        .animation(islandSpring, value: showsMediaCompactStandby)
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
        .onPreferenceChange(IslandPanelSizeKey.self) { size in
            guard viewModel.isExpanded || focusTimer.showsCompactStandby || showsMediaCompactStandby else { return }
            guard size.width > 1, size.height > 1 else { return }
            var resolved = size
            // 番茄：高度始终不低于态下限；宽度仅终局抬升（选时等由内容测量，避免右侧虚空）。
            if viewModel.isExpanded,
               runtime.activeID == FocusTimerWidget.manifest.id
            {
                let floor = FocusTimerContentSize.panelSize(
                    phase: focusTimer.phase,
                    notchHeight: viewModel.notchHeight
                )
                let floorWidth = FocusTimerContentSize.shouldFloorWidth(phase: focusTimer.phase)
                // 终局：宽高都不得低于下限（矮框会把备注裁出可点区）。
                let needFloorWidth = floorWidth && resolved.width + 0.5 < floor.width
                let needFloorHeight = resolved.height + 0.5 < floor.height
                if needFloorWidth || needFloorHeight {
                    AppLog.warn("Island", "番茄 Preference 已按下限校正", [
                        "prefW": Int(resolved.width),
                        "prefH": Int(resolved.height),
                        "floorW": Int(floor.width),
                        "floorH": Int(floor.height),
                        "floorWidth": floorWidth,
                        "phase": focusTimer.phase.rawValue
                    ])
                    resolved = CGSize(
                        width: floorWidth ? max(resolved.width, floor.width) : resolved.width,
                        height: max(resolved.height, floor.height)
                    )
                }
            }
            viewModel.applyMeasuredPanelSize(resolved)
        }
        .onAppear {
            syncCompactPanelSizeIfNeeded()
        }
        .onChange(of: viewModel.appearance) { _, _ in
            syncCompactPanelSizeIfNeeded()
        }
        .onChange(of: focusTimer.showsCompactStandby) { _, _ in
            syncCompactPanelSizeIfNeeded()
        }
        .onChange(of: showsMediaCompactStandby) { _, active in
            syncCompactPanelSizeIfNeeded()
            AppLog.info("Media", "播放小岛已更新", [
                "active": active,
                "playing": nowPlaying.snapshot?.isPlaying ?? false,
                "title": String((nowPlaying.snapshot?.title ?? "").prefix(24))
            ])
        }
        .onChange(of: shelfDropTargeted) { _, targeted in
            let active = targeted && shelfDropEnabled
            IslandController.shared?.setShelfDropTargeted(active)
            if active {
                ControlDeckSettings.shared.focusShelfForDrop()
                // 进入双舱由 IslandController 轮询（须 fileDrag）；此处不再单独 setActive(true)，
                // 避免松手后 isTargeted 残影绕过 fileDrag 检查再闪一次。
            } else if IslandController.shared?.isShelfDragSessionActive != true {
                ShelfDropSession.shared.setActive(false, reason: "dropUntargeted")
            }
        }
        .onChange(of: shelfDropEnabled) { _, enabled in
            if !enabled, shelfDropTargeted {
                shelfDropTargeted = false
                IslandController.shared?.setShelfDropTargeted(false)
                ShelfDropSession.shared.setActive(false, reason: "shelfDisabled")
            }
        }
        .onChange(of: shelfSettings.magneticDropCaptureEnabled) { _, enabled in
            if !enabled {
                ShelfDropSession.shared.setActive(false, reason: "magneticDisabled")
                AppLog.info("Shelf", "磁吸拖放已关闭，退出双舱态")
            }
        }
        .onChange(of: bodySize) { _, size in
            AppLog.debug("Island", "岛尺寸已更新", [
                "expanded": viewModel.isExpanded,
                "combo": runtime.isComboPage,
                "w": size.width,
                "h": size.height,
                "radius": appliedBottomRadius,
                "theme": settings.theme.rawValue
            ])
        }
    }

    /// 收起（含番茄待命）时用几何尺寸；展开交给内容 Preference。
    private func syncCompactPanelSizeIfNeeded() {
        if viewModel.isExpanded { return }
        let next = compactSize
        guard abs(next.width - viewModel.panelSize.width) > 0.5
            || abs(next.height - viewModel.panelSize.height) > 0.5
        else { return }
        viewModel.panelSize = next
    }

    private var islandSpring: Animation {
        .spring(response: settings.springDuration, dampingFraction: settings.springDamping)
    }
}

private struct IslandBody: View {
    let isExpanded: Bool
    let notchHeight: CGFloat
    @ObservedObject var runtime: WidgetRuntime
    @ObservedObject private var focusTimer = FocusTimerSession.shared
    @ObservedObject private var nowPlaying = NowPlayingService.shared
    @ObservedObject private var widgetSettings = WidgetSettings.shared
    @ObservedObject private var noticeCenter = IslandNoticeCenter.shared
    @Environment(\.islandPalette) private var palette

    private var usesNotchWingTip: Bool {
        runtime.isTransientNoticePage
            && (noticeCenter.current?.usesNotchWingChrome == true)
    }

    private var usesShortBelowNotchTip: Bool {
        runtime.isTransientNoticePage
            && (noticeCenter.current?.usesShortBelowNotchChrome == true)
    }

    private var usesNotchRightOrbTip: Bool {
        runtime.isTransientNoticePage
            && (noticeCenter.current?.usesNotchRightOrbChrome == true)
    }

    private var hidesPageDots: Bool {
        // 瞬时通知不参与翻页点（含 AI 额度等走普通通知顶距的条）。
        usesNotchWingTip || usesShortBelowNotchTip || usesNotchRightOrbTip || runtime.isTransientNoticePage
    }

    private var showsMediaCompactStandby: Bool {
        MediaCompactPresence.isActive
    }

    /// 收起态内容框高：略小于岛高，上下各留约 2pt 黑边。
    private var compactContentHeight: CGFloat {
        max(0, NotchGeometry.compactPanelHeight(notchHeight: notchHeight) - 4)
    }

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    // 可选顶栏标题（在统一顶距之下）；会议 / 媒体 / 番茄 title 为空，不占行。
                    if showsShellTitle {
                        Text(runtime.activeTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.title)
                            .lineLimit(1)
                            .padding(.horizontal, IslandChrome.contentHorizontal)
                            .padding(.bottom, 4)
                    }

                    WidgetHostView(runtime: runtime)
                        .padding(.horizontal, contentHorizontalInset)
                }
                .padding(.top, contentTopInset)
                .padding(.bottom, contentBottomInset)
                // 角点用 overlay，避免 Spacer 把 fixedSize 撑成无限宽。
                .overlay(alignment: .top) {
                    if !hidesPageDots {
                        IslandPageCornerDots(runtime: runtime)
                            .padding(.top, max(6, notchHeight * 0.22))
                            .allowsHitTesting(false)
                    }
                }
            } else if focusTimer.showsCompactStandby {
                // 左右翼贴胶囊边：用满 compact 宽，内边距略收，避免内容挤在中段。
                FocusTimerStandbyView(snapshot: focusTimer.snapshot)
                    .padding(.horizontal, 8)
                    .frame(
                        width: NotchGeometry.focusTimerCompactWidth,
                        height: compactContentHeight
                    )
                    .allowsHitTesting(false)
            } else if showsMediaCompactStandby, let snap = nowPlaying.snapshot {
                MediaCompactStandbyView(
                    title: snap.title,
                    artwork: snap.artwork,
                    elapsedText: MediaCompactStandbyView.formatElapsed(snap.elapsed),
                    isPlaying: snap.isPlaying
                )
                .padding(.horizontal, 10)
                .frame(
                    width: NotchGeometry.mediaCompactWidth,
                    height: compactContentHeight
                )
                // 悬停展开由 IslandController；点按保留给辅助功能。
                .contentShape(Rectangle())
                .onTapGesture {
                    MediaCompactPresence.openExpandedPanel(reason: "compactTap")
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(L10n.Media.previewStageExpanded)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
    }

    /// 壳层标题行：控制台 / 空态不显示；内容组件 `title` 为空则不显示。
    private var showsShellTitle: Bool {
        !runtime.isTransientNoticePage
            && !runtime.isControlDeckPage
            && !runtime.isShowingEmpty
            && !runtime.activeTitle.isEmpty
    }

    private var chromeSurface: IslandChrome.Surface {
        if usesNotchRightOrbTip { return .notchRightOrb }
        if usesNotchWingTip { return .notchWingTip }
        if usesShortBelowNotchTip { return .shortBelowNotchTip }
        if runtime.isTransientNoticePage { return .notice }
        return .expanded
    }

    private var chromeInsets: IslandChrome.Insets {
        IslandChrome.insets(for: chromeSurface, notchHeight: notchHeight)
    }

    private var contentHorizontalInset: CGFloat {
        chromeInsets.horizontal
    }

    private var contentTopInset: CGFloat {
        // 媒体展开：顶行封面/律动与刘海同带，顶距置 0（勿用负 padding，否则命中区收缩点不中控件）。
        if chromeSurface == .expanded,
           runtime.activeID == MediaNowPlayingWidget.manifest.id
        {
            return 0
        }
        return chromeInsets.top
    }

    private var contentBottomInset: CGFloat {
        // 番茄完成态略收底距；其余一律走 IslandChrome 固定令牌。
        if chromeSurface == .expanded, focusTimer.phase == .completed { return 8 }
        return chromeInsets.bottom
    }
}
