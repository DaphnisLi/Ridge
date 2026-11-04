import SwiftUI

/// 复制成功岛提示：绿底黑勾 +「已复制」；落在刘海正下方短条。
struct ClipboardCopiedIslandView: View {
    /// 无障碍补充（如「已复制 #0070EB」）；视觉始终只显示「已复制」。
    var detail: String? = nil
    var compact: Bool = false

    /// 与设置页强调绿一致（`SettingsChrome.secondary`）。
    private var accentGreen: Color { SettingsChrome.secondary }

    private var barHeight: CGFloat { compact ? 24 : 28 }
    private var iconSide: CGFloat { compact ? 13 : 15 }

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            ZStack {
                Circle()
                    .fill(accentGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: compact ? 7 : 9, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: iconSide, height: iconSide)

            Text(L10n.Shelf.copied)
                .font(.system(size: compact ? 11 : 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 10 : 14)
        .frame(height: barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail?.isEmpty == false ? detail! : L10n.Shelf.copied)
    }
}
