import AppKit
import SwiftUI

/// 久坐起身 tip：左右翼贴刘海（同会议）。
/// 左：环规 +「久坐 30m」；右：+10m 琥珀钮 + 免打扰图标钮。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding。
struct MoveReminderNoticeCard: View {
    let notice: MoveReminderSession.Notice
    /// 设置样张：仍画出按钮，但不触发真实 snooze / mute。
    var isPreview: Bool = false
    var compact: Bool = false
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private let amber = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A
    private let amberSoft = Color(red: 1.0, green: 0.702, blue: 0.251) // #FFB340

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        if compact { return 30 }
        return max(envNotchHeight, 32)
    }

    /// 右翼双钮，贴近会议翼宽，再略收一点。
    private var wingWidth: CGFloat { compact ? 88 : 94 }

    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    /// 环规外框（含描边），避免被根上 `.clipped()` 切掉。
    private var gaugeOuter: CGFloat { compact ? 17 : 19 }
    private var gaugeStroke: CGFloat { compact ? 1.8 : 2.0 }
    private var gaugeInner: CGFloat { gaugeOuter - gaugeStroke }

    /// 环规进度：按活跃分钟相对常见上限估算，至少 0.35。
    private var gaugeProgress: CGFloat {
        let ratio = CGFloat(notice.activeMinutes) / 60
        return min(max(ratio, 0.35), 0.92)
    }

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(L10n.MoveReminder.metricTitle(notice.activeMinutes))，\(L10n.MoveReminder.noticeSubtitle(notice.restMinutes))"
        )
    }

    // MARK: - Left

    private var leftCluster: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: gaugeStroke)
                    .frame(width: gaugeInner, height: gaugeInner)
                Circle()
                    .trim(from: 0, to: gaugeProgress)
                    .stroke(amber, style: StrokeStyle(lineWidth: gaugeStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: gaugeInner, height: gaugeInner)
                Image(systemName: "figure.seated.side.right")
                    .font(.system(size: compact ? 7.5 : 8.5, weight: .bold))
                    .foregroundStyle(amber)
            }
            // 外框吃进描边宽度，勿再被父级 clipped 切一半。
            .frame(width: gaugeOuter, height: gaugeOuter)
            .layoutPriority(1)

            Text(L10n.MoveReminder.metricTitle(notice.activeMinutes))
                .font(.system(size: compact ? 12 : 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .monospacedDigit()
        }
        // 略留左内边，避免翼贴边时环规贴裁切线。
        .padding(.leading, 1)
    }

    // MARK: - Right

    /// 右翼控件边长；锁死正方形/固有高，避免被岛高拉伸。
    private var actionControlSide: CGFloat { compact ? 20 : 22 }

    private var rightCluster: some View {
        HStack(spacing: 5) {
            MoveReminderAppKitPillButton(
                // 「+」略小、「10m」略大；左侧闹钟图标。
                title: L10n.MoveReminder.snoozeShort,
                symbolName: "alarm.fill",
                foreground: NSColor(amberSoft),
                background: NSColor(amber.opacity(0.22)),
                compact: compact,
                enabled: !isPreview
            ) {
                AppLog.info("MoveReminder", "通知：稍后 10 分钟")
                MoveReminderSession.shared.snoozeTenMinutes()
            }
            .frame(height: actionControlSide)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel(L10n.MoveReminder.snoozeTen)
            .layoutPriority(1)

            // 正圆：SwiftUI 画圆底 + AppKit 透明热区，避免 NSButton 被拉成椭圆。
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                MoveReminderAppKitHitTarget(enabled: !isPreview) {
                    AppLog.info("MoveReminder", "通知：今天不再提醒")
                    MoveReminderSession.shared.muteForToday()
                }
            }
            .frame(width: actionControlSide, height: actionControlSide)
            .clipShape(Circle())
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel(L10n.MoveReminder.muteToday)
            .accessibilityAddTraits(.isButton)
            .layoutPriority(1)
        }
    }

    static func previewSample(
        activeMinutes: Int = 30,
        restMinutes: Int = 2,
        compact: Bool = true
    ) -> MoveReminderNoticeCard {
        MoveReminderNoticeCard(
            notice: .init(
                id: "preview",
                activeMinutes: activeMinutes,
                restMinutes: restMinutes
            ),
            isPreview: true,
            compact: compact
        )
    }
}

// MARK: - AppKit 按钮（翼 tip 首击可靠）

private struct MoveReminderAppKitPillButton: NSViewRepresentable {
    let title: String
    let symbolName: String?
    let foreground: NSColor
    let background: NSColor
    let compact: Bool
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> MoveReminderPillNSButton {
        let button = MoveReminderPillNSButton(compact: compact)
        button.target = context.coordinator
        button.action = #selector(Coordinator.tap(_:))
        button.apply(
            title: title,
            symbolName: symbolName,
            foreground: foreground,
            background: background,
            enabled: enabled
        )
        return button
    }

    func updateNSView(_ button: MoveReminderPillNSButton, context: Context) {
        context.coordinator.action = action
        button.apply(
            title: title,
            symbolName: symbolName,
            foreground: foreground,
            background: background,
            enabled: enabled
        )
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap(_ sender: Any?) { action() }
    }
}

private final class MoveReminderPillNSButton: NSButton {
    private let compact: Bool
    private let fixedHeight: CGFloat

    init(compact: Bool) {
        self.compact = compact
        self.fixedHeight = compact ? 20 : 22
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryLight)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = true
        (cell as? NSButtonCell)?.highlightsBy = []
        (cell as? NSButtonCell)?.showsStateBy = []
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let textW = attributedTitle.size().width
        let iconW: CGFloat = image == nil ? 0 : (compact ? 10 : 11)
        let gap: CGFloat = image == nil ? 0 : 3
        let hPad: CGFloat = compact ? 7 : 8
        return NSSize(width: ceil(textW + iconW + gap) + hPad * 2, height: fixedHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func apply(
        title: String,
        symbolName: String?,
        foreground: NSColor,
        background: NSColor,
        enabled: Bool
    ) {
        self.title = title
        isEnabled = enabled
        // 「+」略小，「10m」略大。
        attributedTitle = Self.styledSnoozeTitle(title, compact: compact, foreground: foreground)
        if let symbolName,
           let img = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
           )
        {
            // 闹钟图标略小于「10m」字号。
            let config = NSImage.SymbolConfiguration(pointSize: compact ? 9 : 9.5, weight: .semibold)
            image = img.withSymbolConfiguration(config)
            contentTintColor = foreground
            imagePosition = .imageLeading
            imageHugsTitle = true
        } else {
            image = nil
        }
        layer?.backgroundColor = background.cgColor
        layer?.cornerRadius = fixedHeight / 2
        invalidateIntrinsicContentSize()
    }

    /// `+10m` → 「+」小一号、「10m」大一号。
    private static func styledSnoozeTitle(
        _ title: String,
        compact: Bool,
        foreground: NSColor
    ) -> NSAttributedString {
        let plusSize: CGFloat = compact ? 9.5 : 10
        let bodySize: CGFloat = compact ? 11 : 11.5
        let plusFont = NSFont.systemFont(ofSize: plusSize, weight: .semibold)
        let bodyFont = NSFont.monospacedDigitSystemFont(ofSize: bodySize, weight: .semibold)
        let result = NSMutableAttributedString(string: title)
        let full = NSRange(location: 0, length: result.length)
        result.addAttributes(
            [.font: bodyFont, .foregroundColor: foreground],
            range: full
        )
        if title.hasPrefix("+") {
            result.addAttributes(
                [.font: plusFont, .foregroundColor: foreground],
                range: NSRange(location: 0, length: 1)
            )
        }
        return result
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}

/// 透明热区：外形由 SwiftUI `Circle` 负责，点击仍走 AppKit 首击。
private struct MoveReminderAppKitHitTarget: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> MoveReminderHitNSView {
        let view = MoveReminderHitNSView()
        view.coordinator = context.coordinator
        view.isEnabled = enabled
        return view
    }

    func updateNSView(_ view: MoveReminderHitNSView, context: Context) {
        context.coordinator.action = action
        view.coordinator = context.coordinator
        view.isEnabled = enabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
}

private final class MoveReminderHitNSView: NSView {
    weak var coordinator: MoveReminderAppKitHitTarget.Coordinator?
    var isEnabled = true

    override var intrinsicContentSize: NSSize {
        // 填满 SwiftUI 给定的正方形框。
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        coordinator?.action()
    }
}
