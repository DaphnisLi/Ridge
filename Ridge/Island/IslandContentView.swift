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
            width: viewModel.notchWidth * CGFloat(settings.expandedWidthScale),
            height: viewModel.notchHeight * CGFloat(settings.expandedHeightScale)
        )
    }

    private var bodySize: CGSize {
        viewModel.isExpanded ? expandedSize : compactSize
    }

    /// 上直角、下圆角；半径受宽高限制，避免变宽后圆角被压扁。
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
                contentToken: viewModel.contentToken
            )
            .frame(width: bodySize.width, height: bodySize.height)
            .background(shape.fill(Color.black))
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(islandSpring, value: viewModel.appearance)
        .animation(islandSpring, value: viewModel.contentToken)
        .animation(islandSpring, value: settings.bottomCornerRadius)
        // 倍率只驱动展开态 bodySize；收起时 compactSize 不变。
        .animation(islandSpring, value: settings.expandedWidthScale)
        .animation(islandSpring, value: settings.expandedHeightScale)
        .opacity(viewModel.isHiddenForFullscreen || !viewModel.isVisibleOnDisplay ? 0 : 1)
        .allowsHitTesting(!viewModel.isHiddenForFullscreen && viewModel.isVisibleOnDisplay)
        .onChange(of: appliedBottomRadius) { _, radius in
            AppLog.debug("Island", "下圆角已应用", [
                "radius": radius,
                "expanded": viewModel.isExpanded,
                "w": bodySize.width,
                "h": bodySize.height
            ])
        }
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
