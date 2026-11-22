import SwiftUI

/// 本机电池 tip：满岛 = 方案 01（左笔记本+色点 / 右百分比+电量条）；
/// 半岛 = 原生精雕微舱（笔记本 + 百分比 + 电量条 + 充电黄闪电）。
struct MacBatteryNoticeCard: View {
    let notice: MacBatteryNotice
    var compact: Bool = false
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        if flushSide != nil { return IslandFlushWingStyle.height }
        if compact { return 30 }
        return max(envNotchHeight, 32)
    }

    private var wingWidth: CGFloat { compact ? 96 : 104 }
    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    private var title: String {
        switch notice.kind {
        case .charging: return L10n.MacBattery.chargingTitle
        case .full: return L10n.MacBattery.fullTitle
        case .low: return L10n.MacBattery.lowTitle
        case .unplugged: return L10n.MacBattery.unplugTitle
        }
    }

    private var isPeninsula: Bool { flushSide != nil }

    static func previewSample(
        kind: MacBatteryNotice.Kind,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        let percent: Int
        let threshold: Int
        let detail: String
        switch kind {
        case .charging:
            percent = 78
            threshold = 0
            detail = L10n.MacBattery.chargingDetail
        case .full:
            percent = 100
            threshold = 100
            detail = L10n.MacBattery.fullDetail
        case .low:
            percent = 12
            threshold = 20
            detail = L10n.MacBattery.lowDetail(12, 20)
        case .unplugged:
            percent = 64
            threshold = 0
            detail = L10n.MacBattery.unplugDetail
        }
        let card = MacBatteryNoticeCard(
            notice: MacBatteryNotice(
                id: "preview.mac.\(kind.rawValue)",
                kind: kind,
                percent: percent,
                threshold: threshold,
                detail: detail
            ),
            compact: true,
            flushSide: flushSide,
            bareWingContent: flushSide != nil
        )
        if let flushSide {
            return AnyView(
                IslandFlushWingCapsule(side: flushSide, width: IslandChrome.dualFlushCompactWingWidth) {
                    card
                }
            )
        }
        return AnyView(
            card
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: compact ? 34 : 40)
        )
    }

    var body: some View {
        Group {
            if isPeninsula {
                peninsulaBody
            } else {
                fullWingBody
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(L10n.Battery.tipPercentBadge(notice.percent))")
    }

    // MARK: - 满岛（方案 01）

    private var fullWingBody: some View {
        let accent = MacBatteryTipPalette.fullIslandAccent(for: notice.kind)
        return HStack(spacing: 0) {
            fullLeftCluster(accent: accent)
                .frame(width: wingWidth + notchWidth * 0.35, alignment: .leading)
            Spacer(minLength: 0)
            fullRightCluster(accent: accent)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, compact ? 16 : 20)
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
    }

    private func fullLeftCluster(accent: Color) -> some View {
        let laptopOpacity: Double = {
            switch notice.kind {
            case .unplugged: return 0.50
            case .low: return 1.0
            default: return 0.80
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: compact ? 14 : 15, weight: .medium))
                .foregroundStyle(
                    notice.kind == .low ? accent : Color.white.opacity(laptopOpacity)
                )
                .layoutPriority(1)
            if notice.kind != .unplugged {
                MacBatteryStatusDot(kind: notice.kind, accent: accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fullRightCluster(accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(L10n.Battery.tipPercentBadge(notice.percent))
                .font(.system(
                    size: 12,
                    weight: notice.kind == .unplugged ? .medium : .semibold,
                    design: .monospaced
                ))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
            MacBatteryClassicGlyph(
                percent: notice.percent,
                style: .fullIsland(kind: notice.kind, accent: accent)
            )
        }
    }

    // MARK: - 半岛（原生精雕微舱）

    private var peninsulaBody: some View {
        let colors = MacBatteryTipPalette.peninsulaColors(for: notice.kind)
        // 与外设半岛同口径：左「图标+电量%」/ 右电量条；C 翼约 96 宽，禁再塞条外闪电以免挤掉数字。
        let row = HStack(spacing: 0) {
            HStack(spacing: IslandFlushWingStyle.iconLabelSpacing) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.laptop)
                Text(L10n.Battery.tipPercentBadge(notice.percent))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colors.percent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            MacBatteryClassicGlyph(
                percent: notice.percent,
                style: .peninsula(colors: colors)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if bareWingContent {
            return AnyView(row.islandBareFlushWingContent())
        }
        return AnyView(IslandFlushWingCapsule(side: flushSide ?? .trailing) { row })
    }
}

// MARK: - Palette

enum MacBatteryTipPalette {
    /// 满岛插电 MagSafe 琥珀 `#ff9f0a`
    static let fullCharging = Color(.sRGB, red: 1.0, green: 0.624, blue: 0.039, opacity: 1)
    /// 满岛满电 `#30d158`
    static let fullFull = Color(.sRGB, red: 0.188, green: 0.820, blue: 0.345, opacity: 1)
    /// 满岛低电 `#ff453a`
    static let fullLow = Color(.sRGB, red: 1.0, green: 0.271, blue: 0.227, opacity: 1)

    /// 半岛满电 `#34c759`
    static let peninsulaFull = Color(.sRGB, red: 0.204, green: 0.780, blue: 0.349, opacity: 1)
    /// 半岛低电 `#ff3b30`
    static let peninsulaLow = Color(.sRGB, red: 1.0, green: 0.231, blue: 0.188, opacity: 1)

    /// 插电态满岛/半岛共用琥珀（数字 + 电量条）。
    static let chargingAccent = fullCharging

    static func fullIslandAccent(for kind: MacBatteryNotice.Kind) -> Color {
        switch kind {
        case .charging: return chargingAccent
        case .full: return fullFull
        case .low: return fullLow
        case .unplugged: return Color.white.opacity(0.80)
        }
    }

    struct PeninsulaColors {
        var laptop: Color
        var percent: Color
        var fill: Color
        var border: Color
        var nub: Color
        var boltInside: Bool
    }

    static func peninsulaColors(for kind: MacBatteryNotice.Kind) -> PeninsulaColors {
        switch kind {
        case .charging:
            // 与满岛插电一致：琥珀数字 + 琥珀电量条（条内闪电）。
            return PeninsulaColors(
                laptop: Color.white.opacity(0.80),
                percent: chargingAccent,
                fill: chargingAccent,
                border: chargingAccent.opacity(0.70),
                nub: chargingAccent.opacity(0.70),
                boltInside: true
            )
        case .full:
            return PeninsulaColors(
                laptop: peninsulaFull,
                percent: peninsulaFull,
                fill: peninsulaFull,
                border: peninsulaFull.opacity(0.60),
                nub: peninsulaFull.opacity(0.60),
                boltInside: false
            )
        case .low:
            return PeninsulaColors(
                laptop: peninsulaLow,
                percent: peninsulaLow,
                fill: peninsulaLow,
                border: peninsulaLow.opacity(0.60),
                nub: peninsulaLow.opacity(0.60),
                boltInside: false
            )
        case .unplugged:
            return PeninsulaColors(
                laptop: Color.white.opacity(0.70),
                percent: Color.white.opacity(0.80),
                fill: Color.white.opacity(0.70),
                border: Color.white.opacity(0.25),
                nub: Color.white.opacity(0.25),
                boltInside: false
            )
        }
    }
}

// MARK: - Dot / Glyph

private struct MacBatteryStatusDot: View {
    let kind: MacBatteryNotice.Kind
    let accent: Color

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 6, height: 6)
            .shadow(color: accent.opacity(kind == .low ? 0 : 0.85), radius: kind == .low ? 0 : 3)
            .modifier(MacBatteryDotPulse(kind: kind))
            .accessibilityHidden(true)
    }
}

private struct MacBatteryDotPulse: ViewModifier {
    let kind: MacBatteryNotice.Kind

    func body(content: Content) -> some View {
        switch kind {
        case .charging:
            TimelineView(.animation(minimumInterval: 0.7, paused: false)) { timeline in
                let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.7) % 2
                content.opacity(phase == 0 ? 1 : 0.35)
            }
        case .low:
            TimelineView(.animation(minimumInterval: 0.55, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let pulse = 0.55 + 0.45 * abs(sin(t * .pi / 0.55))
                content
                    .scaleEffect(0.85 + 0.25 * pulse)
                    .opacity(pulse)
            }
        case .full, .unplugged:
            content
        }
    }
}

private enum MacBatteryGlyphStyle {
    case fullIsland(kind: MacBatteryNotice.Kind, accent: Color)
    case peninsula(colors: MacBatteryTipPalette.PeninsulaColors)

    var fill: Color {
        switch self {
        case .fullIsland(let kind, let accent):
            return kind == .unplugged ? Color.white.opacity(0.70) : accent
        case .peninsula(let colors):
            return colors.fill
        }
    }

    var border: Color {
        switch self {
        case .fullIsland(let kind, let accent):
            switch kind {
            case .charging, .full: return accent.opacity(0.70)
            case .low: return accent.opacity(0.80)
            case .unplugged: return Color.white.opacity(0.30)
            }
        case .peninsula(let colors):
            return colors.border
        }
    }

    var nub: Color {
        switch self {
        case .fullIsland(let kind, let accent):
            return kind == .unplugged ? Color.white.opacity(0.40) : accent.opacity(0.70)
        case .peninsula(let colors):
            return colors.nub
        }
    }

    var boltInside: Bool {
        switch self {
        case .fullIsland(let kind, _):
            return kind == .charging
        case .peninsula(let colors):
            return colors.boltInside
        }
    }
}

/// 经典 HIG 电量条；满岛充电闪电画在条内，半岛闪电在条外另置。
private struct MacBatteryClassicGlyph: View {
    let percent: Int
    let style: MacBatteryGlyphStyle

    private let bodyWidth: CGFloat = 22
    private let bodyHeight: CGFloat = 10.5
    private let inset: CGFloat = 1.5

    private var fillRatio: CGFloat {
        min(max(CGFloat(percent) / 100, 0), 1)
    }

    private var fillWidth: CGFloat {
        let inner = bodyWidth - inset * 2
        guard fillRatio > 0 else { return 0 }
        return max(inner * fillRatio, 2.5)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(style.border, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(style.fill)
                    .frame(width: fillWidth, height: bodyHeight - inset * 2)
                    .padding(.leading, inset)
                if style.boltInside {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(style.nub)
                .frame(width: 1.5, height: 4)
        }
        .accessibilityHidden(true)
    }
}
