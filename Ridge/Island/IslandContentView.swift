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
        // 与窗口几何同一钳制：不小于刘海、不超出屏宽。
        // 普通页 = 刘海×3；组合页（多组件）= 两倍高。
        let width = min(max(rawWidth, viewModel.notchWidth), viewModel.maxExpandedWidth)
        let baseH = viewModel.notchHeight * NotchGeometry.fixedExpandedHeightMultiplier
        let height = runtime.isComboPage ? baseH * 2 : baseH
        return CGSize(
            width: NotchGeometry.pixelAlign(width),
            height: NotchGeometry.pixelAlign(height)
        )
    }

    private var bodySize: CGSize {
        viewModel.isExpanded ? expandedSize : compactSize
    }

    private var appliedBottomRadius: CGFloat {
        min(
            CGFloat(settings.bottomCornerRadius),
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
                runtime: runtime
            )
            .frame(width: bodySize.width, height: bodySize.height)
            .background(shape.fill(palette.fill))
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.islandPalette, palette)
        .animation(islandSpring, value: viewModel.appearance)
        .animation(islandSpring, value: runtime.contentEpoch)
        .animation(islandSpring, value: settings.bottomCornerRadius)
        .animation(islandSpring, value: settings.expandedWidth)
        .animation(islandSpring, value: settings.theme)
        .animation(islandSpring, value: runtime.isComboPage)
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
    @ObservedObject var runtime: WidgetRuntime
    @Environment(\.islandPalette) private var palette

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    if !runtime.isShowingEmpty {
                        if !runtime.activeTitle.isEmpty {
                            HStack {
                                Text(runtime.activeTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.title)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        } else {
                            Color.clear.frame(height: 10)
                        }
                    } else {
                        Color.clear.frame(height: 10)
                    }

                    WidgetHostView(runtime: runtime)
                        .padding(.horizontal, 12)
                        .padding(.bottom, runtime.isShowingEmpty ? 16 : 10)
                }
            } else {
                Color.clear
            }
        }
    }
}
