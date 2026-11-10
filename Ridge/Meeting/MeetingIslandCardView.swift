import SwiftUI

/// 会前提示紧迫度：稿面三态（充裕绿 / 临近琥珀 / 紧急红）。
enum MeetingLeadUrgency: String, CaseIterable, Identifiable, Hashable {
    case relaxed
    case warning
    case critical

    var id: String { rawValue }

    /// >5 分绿；≤5 且 >2 分琥珀；≤2 分（含已开始）红。
    static func resolve(secondsToStart: TimeInterval) -> MeetingLeadUrgency {
        if secondsToStart > 5 * 60 { return .relaxed }
        if secondsToStart > 2 * 60 { return .warning }
        return .critical
    }

    /// 系统绿 #34C759 / 琥珀 #FF9500 / 猩红 #FF3B30。
    var accent: Color {
        switch self {
        case .relaxed:
            return Color(red: 0.204, green: 0.780, blue: 0.349)
        case .warning:
            return Color(red: 1.0, green: 0.584, blue: 0.0)
        case .critical:
            return Color(red: 1.0, green: 0.231, blue: 0.188)
        }
    }

    var settingsTint: Color { accent }

    var symbolName: String {
        switch self {
        case .relaxed: return "calendar"
        case .warning: return "video.fill"
        case .critical: return "dot.radiowaves.left.and.right"
        }
    }

    var stageTitle: String {
        switch self {
        case .relaxed: return L10n.Meeting.urgencyRelaxed
        case .warning: return L10n.Meeting.urgencyWarning
        case .critical: return L10n.Meeting.urgencyCritical
        }
    }

    var stageBadge: String {
        switch self {
        case .relaxed: return L10n.Meeting.urgencyRelaxedBadge
        case .warning: return L10n.Meeting.urgencyWarningBadge
        case .critical: return L10n.Meeting.urgencyCriticalBadge
        }
    }

    var joinTitle: String {
        L10n.Meeting.joinEnter
    }

    /// 倒计时数字色：充裕白字，临近/紧急跟强调色。
    var timerColor: Color {
        switch self {
        case .relaxed: return .white
        case .warning, .critical: return accent
        }
    }

    var joinForeground: Color {
        switch self {
        case .relaxed: return .black
        case .warning: return Color(red: 0.984, green: 0.749, blue: 0.141)
        case .critical: return .white
        }
    }

    var joinBackground: Color {
        switch self {
        case .relaxed: return .white
        case .warning: return accent.opacity(0.25)
        case .critical: return accent
        }
    }

    var joinBorder: Color? {
        switch self {
        case .warning: return accent.opacity(0.40)
        case .relaxed, .critical: return nil
        }
    }
}

/// 会议岛 tip：左翼图标+标题 · 中置纯黑刘海 · 右翼脉冲+MM:SS+进入。
/// 壳层 `usesNotchWingChrome`；外形上直角、下圆角（贴顶融刘海）。
/// 根视图禁止外圈 padding。
struct MeetingIslandCardView: View {
    let title: String
    let secondsToStart: TimeInterval
    let showJoin: Bool
    let showAuth: Bool
    var compact: Bool = false
    var previewNotchWidth: CGFloat = 110
    var onJoin: (() -> Void)?
    var onRequestAuth: (() -> Void)?

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var urgency: MeetingLeadUrgency {
        MeetingLeadUrgency.resolve(secondsToStart: secondsToStart)
    }

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        if compact { return 30 }
        return max(envNotchHeight, 32)
    }

    /// 左右翼等宽，决定整岛宽度；内容用 overlay 左右叠，不靠翼宽硬裁按钮。
    private var wingWidth: CGFloat { compact ? 90 : 98 }
    /// 标题可伸进刘海；右翼控件整体左移后，标题少占一点刘海，避免撞上倒计时。
    private var titleMaxWidth: CGFloat {
        let iconSlot: CGFloat = compact ? 21 : 22
        return wingWidth - iconSlot + notchWidth * 0.48
    }

    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    var body: some View {
        // 左右 / 底外边距只由壳层 `IslandChrome`（notchWing）提供；根上禁止再叠 padding。
        // 岛宽由双翼+刘海占位固定；左右内容 overlay：右侧固有宽贴右并伸进刘海（整体左移），按钮文字不被压扁。
        HStack(spacing: 0) {
            Color.clear
                .frame(width: wingWidth)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: notchWidth)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: wingWidth)
                .accessibilityHidden(true)
        }
        .frame(width: totalWidth, height: barHeight)
        .overlay(alignment: .leading) {
            leftCluster
                .frame(maxWidth: wingWidth + notchWidth * 0.48, alignment: .leading)
        }
        .overlay(alignment: .trailing) {
            rightCluster
                .fixedSize(horizontal: true, vertical: false)
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Left

    private var leftCluster: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(urgency.accent.opacity(0.20))
                Image(systemName: urgency.symbolName)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(urgency.accent)
            }
            .frame(width: compact ? 15 : 16, height: compact ? 15 : 16)
            .layoutPriority(1)

            Text(title)
                .font(.system(size: compact ? 10.5 : 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: titleMaxWidth, alignment: .leading)
        }
    }

    // MARK: - Right

    private var rightCluster: some View {
        HStack(spacing: 6) {
            MeetingLeadPulseDot(accent: urgency.accent)
            Text(Self.countdownText(secondsToStart: secondsToStart))
                .font(.system(size: compact ? 10.5 : 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(urgency.timerColor)
                .lineLimit(1)
                .monospacedDigit()
                .layoutPriority(1)

            if showAuth {
                actionPill(
                    title: L10n.Common.authorize,
                    foreground: .black,
                    background: .white,
                    border: nil,
                    pulsing: false
                ) {
                    onRequestAuth?()
                }
                .layoutPriority(1)
            } else if showJoin {
                actionPill(
                    title: urgency.joinTitle,
                    foreground: urgency.joinForeground,
                    background: urgency.joinBackground,
                    border: urgency.joinBorder,
                    pulsing: urgency == .critical
                ) {
                    onJoin?()
                }
                .layoutPriority(1)
                .accessibilityLabel(L10n.Meeting.joinA11y)
            }
        }
    }

    private func actionPill(
        title: String,
        foreground: Color,
        background: Color,
        border: Color?,
        pulsing: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 9.5 : 10, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, compact ? 7 : 8)
                .padding(.vertical, compact ? 2.5 : 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
                .overlay {
                    if let border {
                        Capsule(style: .continuous)
                            .strokeBorder(border, lineWidth: 1)
                    }
                }
                .modifier(MeetingLeadButtonPulseModifier(enabled: pulsing))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var accessibilityText: String {
        let timer = Self.countdownText(secondsToStart: secondsToStart)
        if showAuth {
            return "\(title)，\(timer)，\(L10n.Common.authorize)"
        }
        if showJoin {
            return "\(title)，\(timer)，\(urgency.joinTitle)"
        }
        return "\(title)，\(timer)"
    }

    // MARK: - Formatters / samples

    static func countdownText(secondsToStart: TimeInterval) -> String {
        let total = max(0, Int(ceil(secondsToStart)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 设置 / 库卡样张。
    static func previewSample(
        urgency: MeetingLeadUrgency = .relaxed,
        compact: Bool = false
    ) -> MeetingIslandCardView {
        let seconds: TimeInterval
        let title: String
        switch urgency {
        case .relaxed:
            seconds = 9 * 60 + 42
            title = L10n.Meeting.previewSampleTitleRelaxed
        case .warning:
            seconds = 4 * 60 + 30
            title = L10n.Meeting.previewSampleTitleWarning
        case .critical:
            seconds = 1 * 60 + 15
            title = L10n.Meeting.previewSampleTitleCritical
        }
        return MeetingIslandCardView(
            title: title,
            secondsToStart: seconds,
            showJoin: true,
            showAuth: false,
            compact: compact,
            previewNotchWidth: compact ? 100 : 110
        )
    }
}

// MARK: - Pulse

/// 状态点持续闪：用 `.common` RunLoop 定时器驱动。
/// 灵动岛是非 key 的 LSUIElement 面板，`TimelineView.animation` / `withAnimation` 常不跑。
private struct MeetingLeadPulseDot: View {
    let accent: Color
    private let period: TimeInterval = 0.9
    @State private var phase: CGFloat = 0

    var body: some View {
        let ringScale = 1 + 1.2 * phase
        let ringOpacity = 0.85 * (1 - phase)
        let coreOpacity = 0.35 + 0.65 * abs(0.5 - phase) * 2
        ZStack {
            Circle()
                .fill(accent.opacity(0.55))
                .frame(width: 6, height: 6)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .opacity(coreOpacity)
        }
        .frame(width: 16, height: 16)
        .onReceive(
            Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
        ) { date in
            let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            phase = CGFloat(t / period)
        }
        .accessibilityHidden(true)
    }
}

private struct MeetingLeadButtonPulseModifier: ViewModifier {
    let enabled: Bool
    @State private var glow = false

    func body(content: Content) -> some View {
        content
            .opacity(enabled && glow ? 0.72 : 1)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
    }
}
