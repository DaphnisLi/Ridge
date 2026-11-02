import AppKit
import SwiftUI

/// 瞬时暂存区：左栏空态用方案一；整岛拖入用方案三悬停吸附态。
struct ShelfDropStagingView: View {
    var highlighted: Bool = false
    /// 整岛拖入态（方案三吸附）。
    var fillsIsland: Bool = false
    /// 铺满左栏矩形（方案一静息）。
    var fillsContainer: Bool = false

    private let accent = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let accentBright = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let emerald = Color(red: 0.31, green: 0.83, blue: 0.40)
    private let glassHover = Color(red: 0.055, green: 0.106, blue: 0.192)

    var body: some View {
        Group {
            if fillsIsland {
                magneticActiveBody
            } else {
                idleSchemeOneBody
            }
        }
        .animation(.easeOut(duration: 0.18), value: highlighted || fillsIsland)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fillsIsland ? L10n.Shelf.dropActiveHint : L10n.Shelf.dropHint)
        .accessibilityHint(fillsIsland ? L10n.Shelf.dropActiveDetail : L10n.Shelf.dropHintDetail)
    }

    // MARK: - 方案一：左栏空态（垂直居中）

    private var idleSchemeOneBody: some View {
        VStack(spacing: 10) {
            idleIcon

            VStack(spacing: 4) {
                Text(L10n.Shelf.dropHint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L10n.Shelf.dropHintDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ramBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: fillsContainer ? .infinity : nil, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            accent.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                        )
                )
        )
    }

    private var idleIcon: some View {
        BobbingBadge(amplitude: 2.5, period: 2.0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 0.85)),
                                Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.90))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)
        }
    }

    private var ramBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(emerald)
                .frame(width: 5, height: 5)
            Text(L10n.Shelf.dropRamBadge)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.top, 2)
    }

    // MARK: - 方案三：整岛拖入悬停吸附态

    private var magneticActiveBody: some View {
        ZStack {
            // 外层：深蓝半透明玻璃 + 蓝色描边光晕
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(glassHover.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.50), lineWidth: 1.5)
                )
                .shadow(color: accentBright.opacity(0.28), radius: 28, y: 8)

            // 内层落点舱
            VStack(spacing: 10) {
                magneticIcon

                VStack(spacing: 3) {
                    Text(L10n.Shelf.dropActiveHint)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(0.3)
                        .multilineTextAlignment(.center)

                    Text(L10n.Shelf.dropActiveDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.75, green: 0.86, blue: 1.0).opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(accent.opacity(0.80), lineWidth: 1.5)
                    )
                    .shadow(color: accent.opacity(0.28), radius: 16, y: 0)
            )
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var magneticIcon: some View {
        BobbingBadge(amplitude: 3.0, period: 0.9) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent)
                    .shadow(color: accent.opacity(0.55), radius: 12, y: 3)

                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
        }
    }
}

/// 整块徽章上下轻浮（蓝底 + 符号一起动）。
private struct BobbingBadge<Content: View>: View {
    var amplitude: CGFloat = 2.5
    var period: Double = 2.0
    @ViewBuilder var content: () -> Content

    @State private var bobbing = false

    var body: some View {
        content()
            .offset(y: bobbing ? amplitude : -amplitude)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    bobbing = true
                }
            }
    }
}
