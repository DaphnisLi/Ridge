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
        let width = min(max(rawWidth, viewModel.notchWidth), viewModel.maxExpandedWidth)
        return CGSize(
            width: NotchGeometry.pixelAlign(width),
            height: NotchGeometry.pixelAlign(
                viewModel.notchHeight * NotchGeometry.fixedExpandedHeightMultiplier
            )
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

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: appliedBottomRadius)
        return ZStack(alignment: .top) {
            IslandBody(
                isExpanded: viewModel.isExpanded,
                runtime: runtime
            )
            .frame(width: bodySize.width, height: bodySize.height)
            // 黑底就是形状本身，再 clip 内容；不要给矩形上色再靠 Shape 插值裁切。
            .background(shape.fill(Color.black))
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(islandSpring, value: viewModel.appearance)
        .animation(islandSpring, value: runtime.contentEpoch)
        .animation(islandSpring, value: settings.bottomCornerRadius)
        .animation(islandSpring, value: settings.expandedWidth)
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
        .onChange(of: bodySize) { _, size in
            AppLog.debug("Island", "岛尺寸已更新", [
                "expanded": viewModel.isExpanded,
                "w": size.width,
                "h": size.height,
                "radius": appliedBottomRadius
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

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    if !runtime.isShowingEmpty {
                        HStack {
                            Text(runtime.activeTitle.isEmpty ? "Ridge" : runtime.activeTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
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
