import SwiftUI

/// 取色引导：左「左键取色」、右「Esc 取消」贴岛左右外缘；中间留刘海宽。
/// 左右外边距只由壳层 `IslandChrome.contentHorizontal` 提供，此处不再加翼宽假边距、也不往中缝挤文案。
struct ColorPickTipIslandView: View {
    /// 预览用色点；实况取色引导可用强调蓝。
    var accent: Color = Color(red: 0.0, green: 0.44, blue: 0.92)
    var compact: Bool = false
    /// 设置预览无真实刘海时的中缝宽度。
    var previewNotchWidth: CGFloat = 160

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 120)
    }

    private var barHeight: CGFloat {
        if compact { return 30 }
        return max(envNotchHeight, 28)
    }

    /// 左右翼最小宽：够放下文案，文案 leading / trailing 贴外缘。
    private var wingMinWidth: CGFloat { compact ? 88 : 100 }
    /// 相对外缘再往中缝挪一点点。
    private var nudgeInward: CGFloat { 16 }

    private var iconSize: CGFloat { compact ? 12 : 13 }
    private var labelFont: Font {
        .system(size: compact ? 11 : 12, weight: .semibold)
    }

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
                .padding(.leading, nudgeInward)
                .frame(minWidth: wingMinWidth, maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: notchWidth)
                .accessibilityHidden(true)
            escCapsule
                .padding(.trailing, nudgeInward)
                .frame(minWidth: wingMinWidth, maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: notchWidth + wingMinWidth * 2, height: barHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Shelf.colorPickFirstTip)
    }

    private var leftCluster: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "eyedropper")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)

                Circle()
                    .fill(accent)
                    .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.85), lineWidth: 1)
                    )
                    .offset(x: 1, y: -1)
            }

            Text(L10n.Shelf.colorPickTipLeft)
                .font(labelFont)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
    }

    private var escCapsule: some View {
        HStack(spacing: 4) {
            Text("⎋")
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
            Text(L10n.Shelf.colorPickTipEsc)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 3 : 3.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.22))
        )
    }
}
