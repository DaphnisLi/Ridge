import SwiftUI

/// OCR 框选引导：左「正在框选文字…」、右「Esc 取消」贴岛左右外缘；中间留刘海宽。
/// 与取色引导同壳（`usesNotchWingChrome`）；根视图不加外圈 padding。
struct OCRSelectTipIslandView: View {
    var accent: Color = Color(red: 0.0, green: 0.44, blue: 0.92)
    var compact: Bool = false
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

    /// 左侧文案更长，翼宽略大于取色。
    private var leftWingMinWidth: CGFloat { compact ? 128 : 148 }
    private var rightWingMinWidth: CGFloat { compact ? 88 : 100 }
    private var nudgeInward: CGFloat { 16 }

    private var iconSize: CGFloat { compact ? 14 : 15 }
    private var labelFont: Font {
        .system(size: compact ? 11 : 12, weight: .semibold)
    }

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
                .padding(.leading, nudgeInward)
                .frame(minWidth: leftWingMinWidth, maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: notchWidth)
                .accessibilityHidden(true)
            escCapsule
                .padding(.trailing, nudgeInward)
                .frame(minWidth: rightWingMinWidth, maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: notchWidth + leftWingMinWidth + rightWingMinWidth, height: barHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Shelf.ocrSelectTipA11y)
    }

    private var leftCluster: some View {
        HStack(spacing: 7) {
            SelectionCornersGlyph(size: iconSize, color: accent)
            Text(L10n.Shelf.ocrSelectTipLeft)
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

/// 四角框选标记（稿面蓝角）。
private struct SelectionCornersGlyph: View {
    var size: CGFloat
    var color: Color

    var body: some View {
        Canvas { context, canvasSize in
            let stroke = max(1.4, size * 0.12)
            let arm = canvasSize.width * 0.34
            let inset = stroke / 2
            var path = Path()
            // 左上
            path.move(to: CGPoint(x: inset, y: inset + arm))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + arm, y: inset))
            // 右上
            path.move(to: CGPoint(x: canvasSize.width - inset - arm, y: inset))
            path.addLine(to: CGPoint(x: canvasSize.width - inset, y: inset))
            path.addLine(to: CGPoint(x: canvasSize.width - inset, y: inset + arm))
            // 左下
            path.move(to: CGPoint(x: inset, y: canvasSize.height - inset - arm))
            path.addLine(to: CGPoint(x: inset, y: canvasSize.height - inset))
            path.addLine(to: CGPoint(x: inset + arm, y: canvasSize.height - inset))
            // 右下
            path.move(to: CGPoint(x: canvasSize.width - inset - arm, y: canvasSize.height - inset))
            path.addLine(to: CGPoint(x: canvasSize.width - inset, y: canvasSize.height - inset))
            path.addLine(to: CGPoint(x: canvasSize.width - inset, y: canvasSize.height - inset - arm))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
