import SwiftUI

/// 取色引导 tip：左右翼贴刘海（同久坐 / 会议）。
/// 左：吸管 +「左键取色」；右：Esc 取消胶囊。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding。
struct ColorPickTipIslandView: View {
    /// 预览用色点；实况取色引导可用强调蓝。
    var accent: Color = Color(red: 0.0, green: 0.44, blue: 0.92)
    var compact: Bool = false
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        if compact { return 30 }
        return max(envNotchHeight, 32)
    }

    private var wingWidth: CGFloat { compact ? 88 : 94 }

    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    private var iconSize: CGFloat { compact ? 11 : 12 }

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth + notchWidth * 0.28, alignment: .leading)
            Spacer(minLength: 0)
            rightCluster
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Shelf.colorPickFirstTip)
    }

    // MARK: - Left

    private var leftCluster: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "eyedropper")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 15 : 16, height: compact ? 15 : 16)

                Circle()
                    .fill(accent)
                    .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.85), lineWidth: 1)
                    )
                    .offset(x: 1, y: -1)
            }
            .layoutPriority(1)

            Text(L10n.Shelf.colorPickTipLeft)
                .font(.system(size: compact ? 12 : 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
        }
        .padding(.leading, 1)
    }

    // MARK: - Right

    private var rightCluster: some View {
        HStack(spacing: 4) {
            Text("⎋")
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
            Text(L10n.Shelf.colorPickTipEsc)
                .font(.system(size: compact ? 10.5 : 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 2.5 : 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .layoutPriority(1)
    }
}
