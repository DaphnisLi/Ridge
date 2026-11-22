import SwiftUI

/// 岛上 AI 额度瞬时 tip：满岛左右翼贴刘海；双槽一侧 flush 胶囊（✦ + % + 点）。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding。
struct AIUsageIslandCardView: View {
    let providerName: String
    let remainingPercent: Int?
    let stage: AIUsageStage
    let resetsAt: Date?
    let errorMessage: String?
    var compact: Bool = false
    var flushSide: IslandFlushWingStyle.Side? = nil
    /// 真岛双槽：只画内容，不套黑胶囊（对齐音乐左翼）。
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

    /// 左右翼等宽，与会议 tip 同口径。
    private var wingWidth: CGFloat { compact ? 90 : 98 }

    private var leftMaxWidth: CGFloat {
        let iconSlot: CGFloat = compact ? 22 : 24
        return wingWidth - iconSlot + notchWidth * 0.48
    }

    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    var body: some View {
        Group {
            if let flushSide {
                flushCapsule(side: flushSide)
            } else {
                fullWingBody
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var fullWingBody: some View {
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth + notchWidth * 0.48, alignment: .leading)
            Spacer(minLength: 0)
            rightCluster
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
    }

    /// 仅双槽半块：外 ✦ 贴百分比，右侧刘海侧脉冲点；满岛仍走 `fullWingBody` + `stage.accent`。
    private func flushCapsule(side: IslandFlushWingStyle.Side) -> some View {
        let tint = stage.flushAccent
        let row = HStack(spacing: 0) {
            HStack(spacing: IslandFlushWingStyle.iconLabelSpacing) {
                Text("✦")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(percentText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .modifier(AIUsagePingModifier(enabled: stage == .warning || stage == .critical))
        }
        if bareWingContent {
            return AnyView(row.islandBareFlushWingContent())
        }
        return AnyView(IslandFlushWingCapsule(side: side) { row })
    }

    // MARK: - Left

    private var leftCluster: some View {
        HStack(spacing: 6) {
            statusRing
                .layoutPriority(1)
            Text(providerName)
                .font(.system(size: compact ? 10.5 : 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            Text(percentText)
                .font(.system(size: compact ? 10.5 : 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(stage.accent)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(maxWidth: leftMaxWidth, alignment: .leading)
    }

    private var statusRing: some View {
        ZStack {
            Circle()
                .strokeBorder(stage.accent, lineWidth: 2)
                .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
            Circle()
                .fill(stage.accent)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                .modifier(AIUsagePingModifier(enabled: stage == .critical))
        }
        .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
    }

    private var percentText: String {
        if let errorMessage, remainingPercent == nil {
            return "--%"
        }
        return remainingPercent.map { "\($0)%" } ?? "--%"
    }

    // MARK: - Right

    /// 重置文案胶囊：色点 +「重置 … / …m 重置」，底色跟档位走。
    private var rightCluster: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(stage.accent)
                .frame(width: compact ? 4.5 : 5, height: compact ? 4.5 : 5)
                .modifier(AIUsagePingModifier(enabled: stage == .critical))
            Text(Self.resetCountdownText(resetsAt))
                .font(.system(size: compact ? 10 : 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(resetForeground)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 2.5 : 3)
        .background(
            Capsule(style: .continuous)
                .fill(resetBackground)
        )
        .layoutPriority(1)
    }

    private var resetForeground: Color {
        switch stage {
        case .abundant, .unknown:
            return Color.white.opacity(0.90)
        case .warning, .critical:
            return stage.accent
        }
    }

    private var resetBackground: Color {
        switch stage {
        case .abundant, .unknown:
            return Color.white.opacity(0.10)
        case .warning:
            return stage.accent.opacity(0.14)
        case .critical:
            return stage.accent.opacity(0.18)
        }
    }

    private var accessibilityText: String {
        let reset = Self.resetCountdownText(resetsAt)
        if let errorMessage, remainingPercent == nil {
            return "\(providerName)，\(errorMessage)，\(reset)"
        }
        return "\(providerName) \(percentText)，\(reset)"
    }

    // MARK: - Formatters

    /// 设置页等一行摘要（与岛上右翼同文案）。
    static func notchResetBadge(_ date: Date?) -> String {
        resetCountdownText(date)
    }

    /// 重置倒计时三档：
    /// - 24 小时外：`重置 14d 后`
    /// - 24 小时内（且 >1h）：`重置 9h 后`
    /// - 1 小时内：`47m 重置`
    static func resetCountdownText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return L10n.AIUsage.resetUnknown }
        let remain = date.timeIntervalSince(now)
        if remain <= 0 { return L10n.AIUsage.resetSoon }
        let seconds = Int(remain.rounded(.down))
        if seconds > 24 * 3600 {
            let days = max(seconds / 86_400, 1)
            return L10n.AIUsage.resetAfterDays(days)
        }
        if seconds > 3600 {
            let hours = max(seconds / 3600, 1)
            return L10n.AIUsage.resetAfterHours(hours)
        }
        let minutes = max(seconds / 60, 1)
        return L10n.AIUsage.resetInMinutesLeading(minutes)
    }

    /// 设置 / 图鉴样张：百分比默认取用户当前档位阈值；`flushSide` 时只出半岛自身半翼。
    static func previewSample(
        stage: AIUsageStage = .abundant,
        remainingPercent: Int? = nil,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> AIUsageIslandCardView {
        let settings = AIUsageSettings.shared
        let remaining: Int
        let resetOffset: TimeInterval
        switch stage {
        case .abundant:
            remaining = remainingPercent ?? settings.abundantThreshold
            resetOffset = 14 * 86_400
        case .warning:
            remaining = remainingPercent ?? settings.warningThreshold
            resetOffset = 9 * 3600
        case .critical:
            remaining = remainingPercent ?? settings.criticalThreshold
            resetOffset = 47 * 60
        case .unknown:
            remaining = remainingPercent ?? 0
            resetOffset = 3600
        }
        return AIUsageIslandCardView(
            providerName: L10n.AIUsage.providerCursor,
            remainingPercent: remaining,
            stage: stage,
            resetsAt: Date().addingTimeInterval(resetOffset),
            errorMessage: nil,
            compact: compact,
            flushSide: flushSide
        )
    }
}

/// 截流态内点轻微闪烁（对照稿 `animate-ping` 降级，避免撑破行高）。
private struct AIUsagePingModifier: ViewModifier {
    let enabled: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(pulse ? 0.35 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        } else {
            content
        }
    }
}
