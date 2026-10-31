import AppKit
import SwiftUI

struct IslandContentView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings

    private var compactSize: CGSize {
        CGSize(
            width: viewModel.notchWidth * NotchGeometry.compactScale,
            height: viewModel.notchHeight * NotchGeometry.compactScale
        )
    }

    private var expandedSize: CGSize {
        CGSize(
            width: viewModel.notchWidth * NotchGeometry.expandedWidthMultiplier,
            height: viewModel.notchHeight * NotchGeometry.expandedHeightMultiplier
        )
    }

    private var bodySize: CGSize {
        viewModel.isExpanded ? expandedSize : compactSize
    }

    /// 上直角、下圆角；半径受高度限制。
    private var islandShape: UnevenRoundedRectangle {
        let bottom = min(CGFloat(settings.bottomCornerRadius), bodySize.height / 2)
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandBody(
                isExpanded: viewModel.isExpanded,
                contentToken: viewModel.contentToken
            )
            .frame(width: bodySize.width, height: bodySize.height)
            .background(islandShape.fill(Color.black))
            .clipShape(islandShape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(islandSpring, value: viewModel.appearance)
        .animation(islandSpring, value: viewModel.contentToken)
        .animation(islandSpring, value: settings.bottomCornerRadius)
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
    }

    private var islandSpring: Animation {
        .spring(response: settings.springDuration, dampingFraction: settings.springDamping)
    }
}

private struct IslandBody: View {
    let isExpanded: Bool
    let contentToken: Int

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    HStack {
                        Text("Ridge")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Text("悬停展开")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    Spacer(minLength: 4)

                    Text("灵动岛地基")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .id(contentToken)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                    Text("移开后收起")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 4)

                    Spacer(minLength: 8)
                }
            } else {
                Color.clear
            }
        }
    }
}
