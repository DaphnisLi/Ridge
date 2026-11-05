import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandContentView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @ObservedObject var runtime: WidgetRuntime
    @ObservedObject private var controlDeck = ControlDeckSettings.shared
    @ObservedObject private var shelfDropSession = ShelfDropSession.shared
    @ObservedObject private var focusTimer = FocusTimerSession.shared
    @State private var shelfDropTargeted = false

    private var shelfDropEnabled: Bool {
        controlDeck.isModuleEnabled("shelf")
    }

    private var compactSize: CGSize {
        // 番茄计时中：收起态加宽，左右翼展示待命倒计时（对齐 Live Activity）。
        if focusTimer.showsCompactStandby {
            return CGSize(
                width: NotchGeometry.pixelAlign(
                    max(viewModel.notchWidth * NotchGeometry.compactScale, NotchGeometry.focusTimerCompactWidth)
                ),
                height: NotchGeometry.pixelAlign(
                    max(viewModel.notchHeight * NotchGeometry.compactScale, NotchGeometry.focusTimerCompactHeight)
                )
            )
        }
        return CGSize(
            width: NotchGeometry.pixelAlign(viewModel.notchWidth * NotchGeometry.compactScale),
            height: NotchGeometry.pixelAlign(viewModel.notchHeight * NotchGeometry.compactScale)
        )
    }

    /// 可见面板尺寸：收起用刘海/待命；展开用内容测量结果（viewModel.panelSize）。
    private var bodySize: CGSize {
        if viewModel.isExpanded {
            let measured = viewModel.panelSize
            if measured.width > 1, measured.height > 1 {
                return measured
            }
            return compactSize
        }
        return compactSize
    }

    private var appliedBottomRadius: CGFloat {
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

    private var palette: IslandPalette { settings.theme.palette }

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: appliedBottomRadius)
        return ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // AppKit device 色不透明层：比 SwiftUI Color 经透明窗合成更接近刘海漆黑。
                IslandOpaqueFillView(
                    bottomRadius: appliedBottomRadius,
                    fill: settings.theme.nsFillColor
                )
                .frame(width: bodySize.width, height: bodySize.height)

                if shelfDropEnabled, viewModel.isExpanded, shelfDropSession.isActive {
                    // 拖入中：整岛切成暂存区 UI，松手 / 离开后恢复。
                    ShelfDropStagingView(highlighted: true, fillsIsland: true)
                        .padding(.horizontal, IslandChrome.contentHorizontal)
                        .padding(.top, max(28, viewModel.notchHeight + 4))
                        .padding(.bottom, IslandChrome.contentBottom)
                        .frame(width: bodySize.width, height: bodySize.height)
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
                }
            }
            // 面板框跟已测尺寸走；内容用 fixedSize 自撑，避免矮框 clip 把新页热区裁掉。
            .frame(width: bodySize.width, height: bodySize.height, alignment: .top)
            .animation(.easeOut(duration: 0.18), value: shelfDropSession.isActive)
            .clipShape(shape)
            // 整块面板都要可命中，避免透明子区把点击漏给下层页面。
            .contentShape(shape)
            // 货架开启时：整岛接收文件拖入（不限货架小栏）。
            .onDrop(of: [.fileURL], isTargeted: $shelfDropTargeted) { providers in
                guard shelfDropEnabled else { return false }
                AppLog.info("Shelf", "整岛接收拖入", [
                    "providers": providers.count,
                    "expanded": viewModel.isExpanded,
                    "page": runtime.activeID ?? "nil"
                ])
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
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
        .onPreferenceChange(IslandPanelSizeKey.self) { size in
            guard viewModel.isExpanded || focusTimer.showsCompactStandby else { return }
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
        .onChange(of: shelfDropTargeted) { _, targeted in
            let active = targeted && shelfDropEnabled
            IslandController.shared?.setShelfDropTargeted(active)
            if active {
                ControlDeckSettings.shared.focusShelfForDrop()
                ShelfDropSession.shared.setActive(true, reason: "dropTargeted")
            } else if !active {
                // 离开投放区：若控制器侧也未钉住拖入，则退出暂存态。
                if IslandController.shared?.isShelfDragSessionActive != true {
                    ShelfDropSession.shared.setActive(false, reason: "dropUntargeted")
                }
            }
        }
        .onChange(of: shelfDropEnabled) { _, enabled in
            if !enabled, shelfDropTargeted {
                shelfDropTargeted = false
                IslandController.shared?.setShelfDropTargeted(false)
                ShelfDropSession.shared.setActive(false, reason: "shelfDisabled")
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

    private var hidesPageDots: Bool {
        // 瞬时通知不参与翻页点（含 AI 额度等走普通通知顶距的条）。
        usesNotchWingTip || usesShortBelowNotchTip || runtime.isTransientNoticePage
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
                        height: max(
                            0,
                            NotchGeometry.focusTimerCompactHeight - 4
                        )
                    )
                    .allowsHitTesting(false)
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

    private var contentHorizontalInset: CGFloat {
        IslandChrome.contentHorizontal
    }

    private var contentTopInset: CGFloat {
        if usesNotchWingTip { return IslandChrome.compactTipTopInset }
        if usesShortBelowNotchTip {
            return IslandChrome.shortTipTopInset(notchHeight: notchHeight)
        }
        if runtime.isTransientNoticePage {
            return IslandChrome.noticeTopInset(notchHeight: notchHeight)
        }
        return IslandChrome.expandedTopInset(notchHeight: notchHeight)
    }

    private var contentBottomInset: CGFloat {
        if usesNotchWingTip { return IslandChrome.compactTipBottom }
        if usesShortBelowNotchTip { return IslandChrome.shortTipBottom }
        if focusTimer.phase == .completed { return 8 }
        return IslandChrome.contentBottom
    }
}
