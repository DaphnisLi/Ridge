import SwiftUI

/// 取色引导：刘海正下方胶囊短条（图标 +「左键取色」+ Esc 取消）。
/// 根视图禁止外圈 padding；壳层走 `usesShortBelowNotchChrome`。
struct ColorPickTipIslandView: View {
    /// 预览用色点；实况取色引导可用强调蓝。
    var accent: Color = Color(red: 0.0, green: 0.44, blue: 0.92)
    var compact: Bool = false

    private var barHeight: CGFloat { compact ? 24 : 28 }
    private var iconSize: CGFloat { compact ? 12 : 13 }
    private var labelFont: Font {
        .system(size: compact ? 11 : 13, weight: .medium)
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
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

            escCapsule
        }
        // 左右/底外边距只由壳层 `IslandChrome`（shortBelowNotch）提供；根上禁止再叠。
        .frame(height: barHeight)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Shelf.colorPickFirstTip)
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
        .padding(.vertical, compact ? 2.5 : 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.22))
        )
    }
}
