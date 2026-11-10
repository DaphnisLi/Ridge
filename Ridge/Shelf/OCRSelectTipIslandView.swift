import SwiftUI

/// OCR 框选引导 tip：左右翼贴刘海（同久坐 / 取色）。
/// 左：框选角标 +「正在框选…」；右：Esc 取消胶囊。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding。
struct OCRSelectTipIslandView: View {
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

    private var iconSize: CGFloat { compact ? 12 : 13 }

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
        .accessibilityLabel(L10n.Shelf.ocrSelectTipA11y)
    }

    // MARK: - Left

    private var leftCluster: some View {
        HStack(spacing: 6) {
            SelectionCornersGlyph(size: iconSize, color: accent)
                .layoutPriority(1)
            Text(L10n.Shelf.ocrSelectTipLeft)
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
