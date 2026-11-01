import AppKit
import SwiftUI

struct IslandContentView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @ObservedObject var runtime: WidgetRuntime

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
            IslandBody(
                isExpanded: viewModel.isExpanded,
                notchHeight: viewModel.notchHeight,
                runtime: runtime
            )
            .frame(width: bodySize.width, height: bodySize.height)
            .background(shape.fill(palette.fill))
            .clipShape(shape)
            // 整块面板都要可命中，避免透明子区把点击漏给下层页面。
            .contentShape(shape)
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
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
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
                VStack(spacing: 0) {
                    topChrome

                    WidgetHostView(runtime: runtime)
                        .padding(.horizontal, 12)
                        .padding(.bottom, runtime.isShowingEmpty ? 16 : 10)
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
            .padding(.top, 12)
        } else if !runtime.isShowingEmpty {
            // 会议等自带标题的内容页：只留刘海安全距，不再叠一层顶栏。
            Color.clear
                .frame(height: max(8, notchHeight - 6))
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 10)
        }
    }
}
