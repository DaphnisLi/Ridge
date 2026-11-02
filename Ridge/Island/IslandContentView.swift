import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandContentView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @ObservedObject var runtime: WidgetRuntime
    @ObservedObject private var controlDeck = ControlDeckSettings.shared
    @ObservedObject private var shelfDropSession = ShelfDropSession.shared
    @State private var shelfDropTargeted = false

    private var shelfDropEnabled: Bool {
        controlDeck.isModuleEnabled("shelf")
    }

    private var compactSize: CGSize {
        CGSize(
            width: NotchGeometry.pixelAlign(viewModel.notchWidth * NotchGeometry.compactScale),
            height: NotchGeometry.pixelAlign(viewModel.notchHeight * NotchGeometry.compactScale)
        )
    }

    private var expandedSize: CGSize {
        let rawWidth = CGFloat(settings.expandedWidth)
        let layout: NotchGeometry.ExpandedLayout = {
            if runtime.isControlDeckPage { return .controlDeck }
            if runtime.isTransientNoticePage { return .notice }
            if runtime.isComboPage { return .combo }
            return .standard
        }()
        // 与 NotchGeometry.expandedSize 同一套规则（控制台会抬到约 660×300+）。
        let preferred = runtime.isControlDeckPage
            ? max(rawWidth, NotchGeometry.controlDeckPreferredWidth)
            : rawWidth
        let width = min(max(preferred, viewModel.notchWidth), viewModel.maxExpandedWidth)
        let baseH = viewModel.notchHeight * NotchGeometry.fixedExpandedHeightMultiplier
        let height: CGFloat = {
            switch layout {
            case .standard: return baseH
            case .combo: return baseH * 2
            case .controlDeck:
                return max(
                    viewModel.notchHeight * NotchGeometry.controlDeckHeightMultiplier,
                    NotchGeometry.controlDeckMinHeight
                )
            case .notice:
                return max(
                    viewModel.notchHeight * NotchGeometry.noticeHeightMultiplier,
                    viewModel.notchHeight + 34
                )
            }
        }()
        return CGSize(
            width: NotchGeometry.pixelAlign(width),
            height: NotchGeometry.pixelAlign(height)
        )
    }

    private var bodySize: CGSize {
        viewModel.isExpanded ? expandedSize : compactSize
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
                if shelfDropEnabled, viewModel.isExpanded, shelfDropSession.isActive {
                    // 拖入中：整岛切成暂存区 UI，松手 / 离开后恢复。
                    ShelfDropStagingView(highlighted: true, fillsIsland: true)
                        .padding(.horizontal, 16)
                        .padding(.top, max(28, viewModel.notchHeight + 4))
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    IslandBody(
                        isExpanded: viewModel.isExpanded,
                        notchHeight: viewModel.notchHeight,
                        runtime: runtime
                    )
                }
            }
            .frame(width: bodySize.width, height: bodySize.height)
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
        .animation(islandSpring, value: viewModel.appearance)
        .animation(islandSpring, value: runtime.contentEpoch)
        .animation(islandSpring, value: settings.bottomCornerRadius)
        .animation(islandSpring, value: settings.expandedWidth)
        .animation(islandSpring, value: settings.theme)
        .animation(islandSpring, value: runtime.isComboPage)
        .animation(islandSpring, value: runtime.isControlDeckPage)
        .animation(islandSpring, value: runtime.isTransientNoticePage)
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
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

    private var islandSpring: Animation {
        .spring(response: settings.springDuration, dampingFraction: settings.springDamping)
    }
}

private struct IslandBody: View {
    let isExpanded: Bool
    let notchHeight: CGFloat
    @ObservedObject var runtime: WidgetRuntime
    @Environment(\.islandPalette) private var palette

    var body: some View {
        Group {
            if isExpanded {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        // 瞬时通知：不再单独垫 topChrome，整块内容由下方统一 padding.top 下推。
                        if !runtime.isTransientNoticePage {
                            topChrome
                        }

                        WidgetHostView(runtime: runtime)
                            .padding(.horizontal, 12)
                            .padding(
                                .top,
                                runtime.isTransientNoticePage
                                    ? max(32, (notchHeight * 0.5 + 4) * 2)
                                    : 0
                            )
                            .padding(
                                .bottom,
                                runtime.isTransientNoticePage
                                    ? 12
                                    : (runtime.isShowingEmpty ? 16 : 8)
                            )
                    }

                    // 左上 / 右上：前面几页 / 后面几页。
                    IslandPageCornerDots(runtime: runtime)
                        .padding(.top, max(6, notchHeight * 0.22))
                        .allowsHitTesting(false)
                }
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var topChrome: some View {
        if runtime.isControlDeckPage {
            // 控制台不显示标题行；顶部留出刘海盲区，避免按钮落在摄像头缺口上点不到。
            Color.clear
                .frame(height: max(8, notchHeight - 6))
                .accessibilityHidden(true)
        } else if !runtime.isShowingEmpty, !runtime.activeTitle.isEmpty {
            HStack {
                Text(runtime.activeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, max(12, notchHeight + 2))
        } else if !runtime.isShowingEmpty {
            // 会议 / 媒体等自带标题的内容页：留足刘海盲区，避免曲名顶进摄像头缺口。
            Color.clear
                .frame(height: max(12, notchHeight + 2))
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 10)
        }
    }
}
