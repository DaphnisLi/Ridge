import SwiftUI

/// OCR 框选引导：刘海正下方胶囊短条（框选图标 +「正在框选…」+ Esc 取消）。
/// 与取色同壳（`usesShortBelowNotchChrome`）；根视图不加外圈 padding。
struct OCRSelectTipIslandView: View {
    var accent: Color = Color(red: 0.0, green: 0.44, blue: 0.92)
    var compact: Bool = false

    private var barHeight: CGFloat { compact ? 24 : 28 }
    private var iconSize: CGFloat { compact ? 14 : 15 }
    private var labelFont: Font {
        .system(size: compact ? 11 : 13, weight: .medium)
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            SelectionCornersGlyph(size: iconSize, color: accent)
            Text(L10n.Shelf.ocrSelectTipLeft)
                .font(labelFont)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
            escCapsule
        }
        // 左右/底外边距只由壳层 `IslandChrome`（shortBelowNotch）提供；根上禁止再叠。
        .frame(height: barHeight)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Shelf.ocrSelectTipA11y)
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
