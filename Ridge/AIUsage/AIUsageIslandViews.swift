import SwiftUI

/// 岛上 AI 额度瞬时胶囊（新稿单行）：双环点 + 名 + 彩色% + 重置时间 + 剩余徽章。
/// 总宽随左右文案自适应；中间空隙固定。根视图禁止外圈 padding。
struct AIUsageIslandCardView: View {
    /// 左右文案区之间的固定空隙（右侧变长时整岛变宽，中间不变）。
    static let middleGap: CGFloat = 48

    let providerName: String
    let remainingPercent: Int?
    let stage: AIUsageStage
    let resetsAt: Date?
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
            Color.clear
                .frame(width: Self.middleGap)
            rightCluster
        }
        // 总宽 = 左 + 固定中缝 + 右；勿写死整岛宽度。
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Left

    private var leftCluster: some View {
        HStack(spacing: 8) {
            statusRing
            Text(providerName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(percentText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(stage.accent)
                .lineLimit(1)
        }
    }

    private var statusRing: some View {
        ZStack {
            Circle()
                .strokeBorder(stage.accent, lineWidth: 2)
                .frame(width: 14, height: 14)
            Circle()
                .fill(stage.accent)
                .frame(width: 6, height: 6)
                .modifier(AIUsagePingModifier(enabled: stage == .critical))
        }
        .frame(width: 14, height: 14)
    }

    private var percentText: String {
        if let errorMessage, remainingPercent == nil {
            return "--%"
        }
        return remainingPercent.map { "\($0)%" } ?? "--%"
    }

    // MARK: - Right

    private var rightCluster: some View {
        let parts = Self.resetParts(resetsAt)
        return HStack(spacing: 8) {
            Text(parts.schedule)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(red: 0.612, green: 0.639, blue: 0.686))
                .lineLimit(1)
            Text(parts.remain)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(remainForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(remainBackground)
                )
                .lineLimit(1)
        }
    }

    private var remainForeground: Color {
        switch stage {
        case .abundant, .unknown:
            return Color.white.opacity(0.90)
        case .warning, .critical:
            return stage.accent
        }
    }

    private var remainBackground: Color {
        switch stage {
        case .abundant, .unknown:
            return Color.white.opacity(0.10)
        case .warning:
            return stage.accent.opacity(0.10)
        case .critical:
            return stage.accent.opacity(0.15)
        }
    }

    private var accessibilityText: String {
        let parts = Self.resetParts(resetsAt)
        if let errorMessage, remainingPercent == nil {
            return "\(providerName)，\(errorMessage)，\(parts.schedule) \(parts.remain)"
        }
        return "\(providerName) \(percentText)，\(parts.schedule) \(parts.remain)"
    }

    // MARK: - Formatters

    struct ResetParts: Hashable {
        var schedule: String
        var remain: String
    }

    /// 设置页等仍可能要一行摘要。
    static func notchResetBadge(_ date: Date?) -> String {
        let parts = resetParts(date)
        return "\(parts.schedule) · \(parts.remain)"
    }

    /// 排期邻近档：决定「余」用天，还是小时/分钟。
    private enum ResetProximity {
        /// 月日 + 时间；余只显示天。
        case calendarDate
        /// 明日 / 今天；余：>60 分钟只显示小时，否则只显示分钟。
        case near
    }

    static func resetParts(_ date: Date?) -> ResetParts {
        guard let date else {
            return ResetParts(schedule: L10n.AIUsage.resetUnknown, remain: L10n.AIUsage.resetSoonShort)
        }
        let remain = date.timeIntervalSinceNow
        let (schedule, proximity) = scheduleText(date)
        return ResetParts(schedule: schedule, remain: remainText(remain, proximity: proximity))
    }

    private static func scheduleText(_ date: Date) -> (String, ResetProximity) {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "zh_CN")
        // 今天：只展示几点 +「重置」。
        if Calendar.current.isDateInToday(date) {
            clock.dateFormat = "HH:mm"
            return ("\(clock.string(from: date)) \(L10n.AIUsage.resetVerb)", .near)
        }
        // 明日：展示「明日 HH:mm 重置」。
        if Calendar.current.isDateInTomorrow(date) {
            clock.dateFormat = "HH:mm"
            return (L10n.AIUsage.resetTomorrow(clock.string(from: date)), .near)
        }
        // 更远：月日 + 时间。
        clock.dateFormat = "M月d日 HH:mm"
        return ("\(clock.string(from: date)) \(L10n.AIUsage.resetVerb)", .calendarDate)
    }

    private static func remainText(_ remain: TimeInterval, proximity: ResetProximity) -> String {
        if remain <= 0 { return L10n.AIUsage.resetSoonShort }
        let totalSeconds = Int(remain)
        switch proximity {
        case .calendarDate:
            // 只展示天（至少 1 天；不足整天仍按整天向下取整，最少 1）。
            let days = max(totalSeconds / 86_400, 1)
            return L10n.AIUsage.resetInDays(days)
        case .near:
            // > 60 分钟 → 只显示小时；≤ 60 分钟 → 只显示分钟。
            if totalSeconds > 60 * 60 {
                let hours = max(totalSeconds / 3600, 1)
                return L10n.AIUsage.resetInHours(hours)
            }
            let minutes = max(totalSeconds / 60, 1)
            return L10n.AIUsage.resetInMinutes(minutes)
        }
    }

    /// 设置预览样张：百分比默认取用户当前档位阈值（非写死 60/30/10）；真提示一律用探针实时剩余。
    static func previewSample(
        stage: AIUsageStage = .abundant,
        remainingPercent: Int? = nil
    ) -> AIUsageIslandCardView {
        let settings = AIUsageSettings.shared
        let remaining: Int
        let resetOffset: TimeInterval
        switch stage {
        case .abundant:
            remaining = remainingPercent ?? settings.abundantThreshold
            resetOffset = 15 * 86_400
        case .warning:
            remaining = remainingPercent ?? settings.warningThreshold
            resetOffset = 10 * 3600
        case .critical:
            remaining = remainingPercent ?? settings.criticalThreshold
            resetOffset = 48 * 60
        case .unknown:
            remaining = remainingPercent ?? 0
            resetOffset = 3600
        }
        return AIUsageIslandCardView(
            providerName: L10n.AIUsage.providerCursor,
            remainingPercent: remaining,
            stage: stage,
            resetsAt: Date().addingTimeInterval(resetOffset),
            errorMessage: nil
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
