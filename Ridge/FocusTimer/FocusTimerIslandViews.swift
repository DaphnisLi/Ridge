import AppKit
import SwiftUI

/// 收起待命与媒体小岛对齐：左环直径 = 封面边长。
/// 库卡待命外框见 `WidgetSamplePreview.meetingMatchedCompactChrome`（290×30）；详情页仍用本文件样张固有尺寸。
enum FocusTimerCompactMetrics {
    /// 与 `MediaCompactStandbyView` 封面 22 一致，避免环偏大把岛撑高。
    static let progressRingDiameter: CGFloat = 22
    static let progressRingLineWidth: CGFloat = 2.5
    static let progressRingIconPointSize: CGFloat = 9
    /// 满岛待命相对顶边略下移，避免贴顶发挤。
    static let standbyTopNudge: CGFloat = 2
}

/// 番茄面板下限：选时走内容 `fixedSize` + IslandChrome；
/// 计时 / 加时不走展开面板；终局改贴刘海双翼 tip（顶距 0，无展开页大顶空）。
enum FocusTimerContentSize {
    /// 终局单侧翼宽（与 `IslandChrome.preparedFocusCompletedWingWidth` 对齐）。
    static var completedWingWidth: CGFloat { IslandChrome.preparedFocusCompletedWingWidth }
    /// 终局中间刘海空隙额外加宽（左右内容略分开，勿贴死硬件宽）。
    static let completedCenterExtra: CGFloat = 8
    /// 设置预览无硬件刘海：翼 tip 顶距为 0；终局真岛底距亦为 0（高=刘海）。
    static var completedPreviewTopInset: CGFloat { 0 }
    static var completedBottomInset: CGFloat { 0 }

    static func minimumContentHeight(phase: FocusTimerPhase) -> CGFloat {
        switch phase {
        case .picking, .running, .overtime, .countUp:
            return 28
        case .completed:
            return FocusTimerCompletedView.noteRowHeight
        }
    }

    /// 展开首帧 / Preference 下限（终局用翼 tip 预备尺寸；计时/加时/正计时不展开）。
    static func panelSize(
        phase: FocusTimerPhase,
        notchHeight: CGFloat,
        notchWidth: CGFloat = 160
    ) -> CGSize {
        switch phase {
        case .completed:
            return IslandChrome.preparedFocusCompletedPanelSize(
                notchWidth: notchWidth + completedCenterExtra,
                notchHeight: notchHeight
            )
        case .picking, .running, .overtime, .countUp:
            return CGSize(
                width: 360 + IslandChrome.horizontalInsetTotal,
                height: IslandChrome.expandedTopInset(notchHeight: notchHeight)
                    + minimumContentHeight(phase: phase)
                    + IslandChrome.contentBottom
            )
        }
    }

    /// Preference 是否应抬升宽度（仅终局）。
    static func shouldFloorWidth(phase: FocusTimerPhase) -> Bool {
        phase == .completed
    }
}

/// 岛面番茄倒计时：选时 / 待命（含加时黄）/ 终局；预览可注入 snapshot。
struct FocusTimerIslandCardView: View {
    let snapshot: FocusTimerSnapshot
    var isExpanded: Bool = true
    var onSelectPreset: (FocusTimerPreset) -> Void = { _ in }
    var onCustomMinutes: (Int) -> Void = { _ in }
    var onStart: () -> Void = {}
    var onStartCountUp: () -> Void = {}
    var onExtend: () -> Void = {}
    var onFinishEarly: () -> Void = {}
    var onToggleCountUpPause: () -> Void = {}
    var onNoteChange: (String) -> Void = { _ in }
    var onSave: () -> Void = {}
    var presets: [FocusTimerPreset] = FocusTimerPreset.defaults
    var extendStepMinutes: Int = 5
    /// 设置样张终局略收翼宽。
    var previewCompactCompleted: Bool = false

    var body: some View {
        Group {
            if snapshot.phase == .running || snapshot.phase == .overtime || snapshot.phase == .countUp {
                // 计时 / 加时 / 正计时：一律待命胶囊，不区分悬停展开。
                FocusTimerStandbyView(
                    snapshot: snapshot,
                    extendStepMinutes: extendStepMinutes,
                    onExtend: onExtend,
                    onFinishEarly: onFinishEarly,
                    onTogglePause: onToggleCountUpPause
                )
            } else if snapshot.phase == .completed {
                // 双翼 tip：固有宽高，壳层 notchWingTip（顶 0）。
                phaseBody
                    .fixedSize(horizontal: true, vertical: true)
            } else {
                // 选时：内容固有尺寸，左右底边距走 IslandChrome，勿再锁死宽。
                phaseBody
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.FocusTimer.widgetName)
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch snapshot.phase {
        case .picking:
            FocusTimerPickingView(
                snapshot: snapshot,
                presets: presets,
                onSelectPreset: onSelectPreset,
                onCustomMinutes: onCustomMinutes,
                onStart: onStart,
                onStartCountUp: onStartCountUp
            )
        case .running, .overtime, .countUp:
            EmptyView()
        case .completed:
            FocusTimerCompletedView(
                snapshot: snapshot,
                onNoteChange: onNoteChange,
                onSave: onSave,
                compact: previewCompactCompleted
            )
        }
    }

    /// 设置预览：按态切换样张。
    static func previewSample(phase: FocusTimerPhase = .running, compact: Bool = false) -> some View {
        let snap: FocusTimerSnapshot = {
            switch phase {
            case .picking: return .pickingPreview
            case .running: return .runningStandbyPreview
            case .overtime: return .overtimePreview
            case .countUp: return .countUpPreview
            case .completed: return .completedPreview
            }
        }()
        return FocusTimerIslandCardView(
            snapshot: snap,
            isExpanded: !compact || phase == .picking || phase == .completed,
            presets: FocusTimerPreset.defaults,
            extendStepMinutes: 5,
            previewCompactCompleted: compact && phase == .completed
        )
    }
}

// MARK: - 1. 标准待命（计时 / 加时唯一岛面）

struct FocusTimerStandbyView: View {
    let snapshot: FocusTimerSnapshot
    /// 双槽一侧：闲时 icon+时长；悬停 morph 操作钮（倒计时 +Nm/结束，正计时 暂停/结束）。
    var flushSide: IslandFlushWingStyle.Side? = nil
    /// 真岛双槽：只画内容，不套黑胶囊。
    var bareWingContent: Bool = false
    var extendStepMinutes: Int = 5
    var onExtend: () -> Void = {}
    var onFinishEarly: () -> Void = {}
    var onTogglePause: () -> Void = {}
    @State private var isWingHovering = false
    /// AppKit 钮按下期间钉住 morph，避免 mouseDown 瞬间 onHover false 把钮 `allowsHitTesting` 掐掉。
    @State private var isWingActionPressing = false
    @State private var wingHoverDismissWork: DispatchWorkItem?
    @ObservedObject private var trailingWingHover = FocusTrailingWingHover.shared

    /// Controller 右翼命中 ∪ 本翼 onHover ∪ 按下钉住。
    private var showsWingActions: Bool {
        isWingHovering || isWingActionPressing || trailingWingHover.isActive
    }

    private var isOvertime: Bool { snapshot.phase == .overtime }
    private var isCountUp: Bool { snapshot.isCountUp }
    /// 正计时绿 / 加时黄 / 倒计时蓝；半块 flush 另用 `flushAccent`，禁止串色。
    private var ringColor: Color {
        if isCountUp {
            return Color(red: 0.45, green: 0.92, blue: 0.58)
        }
        return isOvertime
            ? Color(red: 0.98, green: 0.75, blue: 0.14)
            : Color(red: 0.0, green: 0.44, blue: 0.92)
    }
    private var ringIconColor: Color {
        if isCountUp {
            return Color(red: 0.45, green: 0.92, blue: 0.58)
        }
        return isOvertime
            ? Color(red: 1.0, green: 0.84, blue: 0.40)
            : Color.white.opacity(0.95)
    }
    private var ringFill: Color? {
        isCountUp ? Color(red: 0.10, green: 0.28, blue: 0.18) : nil
    }
    private var ringIcon: String {
        if isCountUp { return "timer" }
        return isOvertime ? "alarm.fill" : "hourglass"
    }
    /// 双翼闲时小标：与满岛环内标一致。
    private var wingIcon: String { ringIcon }
    private var flushAccent: Color {
        if isCountUp { return Color(red: 0.45, green: 0.92, blue: 0.58) }
        return isOvertime ? IslandFlushWingStyle.accentWarning : IslandFlushWingStyle.accentInfo
    }
    private var clockText: String {
        isCountUp
            ? FocusTimerFormatting.countUpClock(snapshot.elapsedSeconds)
            : FocusTimerFormatting.clock(snapshot.remainingSeconds)
    }
    private var statusLabel: String {
        if isCountUp {
            return snapshot.isPaused ? L10n.FocusTimer.paused : L10n.FocusTimer.countUpMode
        }
        return isOvertime ? L10n.FocusTimer.overtimeBadge : L10n.FocusTimer.focusing
    }

    var body: some View {
        if flushSide != nil {
            wingLeadContent(bare: bareWingContent)
        } else {
            fullStandbyBody
        }
    }

    private var fullStandbyBody: some View {
        // 倒计时：左环+剩余，右 +Nm / 停止；正计时：左绿环+已过，右暂停 / 停止。
        // 左右 padding 写在内容内，外层勿再叠，否则固定岛宽会被吃掉导致芯片裁切。
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                FocusTimerProgressRing(
                    progress: snapshot.progress,
                    stroke: ringColor,
                    icon: ringIcon,
                    iconColor: ringIconColor,
                    fill: ringFill
                )
                Text(clockText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    // 正计时：先按分秒占位，出小时再加宽；禁止随「仅秒」文案缩列导致被裁。
                    .frame(
                        minWidth: isCountUp
                            ? NotchGeometry.focusTimerCountUpClockMinWidth(
                                elapsedSeconds: snapshot.elapsedSeconds
                            )
                            : nil,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(2)
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                if isCountUp {
                    FocusTimerStandbyPauseButton(
                        isPaused: snapshot.isPaused,
                        action: onTogglePause
                    )
                    FocusTimerStandbyStopButton(action: onFinishEarly)
                } else {
                    FocusTimerStandbyExtendButton(minutes: extendStepMinutes, action: onExtend)
                    FocusTimerStandbyStopButton(action: onFinishEarly)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(.leading, NotchGeometry.focusTimerStandbyLeadingPadding)
        .padding(.trailing, NotchGeometry.focusTimerStandbyTrailingPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // 相对垂直居中再略下移，加大与顶边的空隙。
        .padding(.top, FocusTimerCompactMetrics.standbyTopNudge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(statusLabel)，\(clockText)")
        .onAppear {
            AppLog.debug("FocusTimer", "满岛待命边距", [
                "leading": Int(NotchGeometry.focusTimerStandbyLeadingPadding),
                "trailing": Int(NotchGeometry.focusTimerStandbyTrailingPadding),
                "countUp": isCountUp,
                "clock": clockText
            ])
        }
    }

    private func wingLeadContent(bare: Bool) -> some View {
        // 双槽半块：闲时外图标|时长|点；悬停 morph 操作钮（勿开媒体大面板，由 Controller 排除右翼）。
        // 整翼 contentShape + Controller trailing 钉住；图标/文字/空白同一热区。
        // 本地 onHover 离开必须清 isWingHovering：此前若因 trailingPinned 跳过清理，指针离岛后 morph 永不恢复数字。
        let spacer = bare
            ? IslandFlushWingStyle.bareContentSpacerMin
            : CGFloat(4)
        let core = ZStack {
            Button {
                revealWingActions(reason: "idleTap")
            } label: {
                wingIdleRow(spacer: spacer)
            }
            .buttonStyle(.plain)
            .opacity(showsWingActions ? 0 : 1)
            .scaleEffect(showsWingActions ? 0.96 : 1)
            .allowsHitTesting(!showsWingActions)

            wingActionsRow
                .opacity(showsWingActions ? 1 : 0)
                .scaleEffect(showsWingActions ? 1 : 0.96)
                .allowsHitTesting(showsWingActions)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.14), value: showsWingActions)

        let filled: AnyView = {
            if bare {
                return AnyView(core.islandBareFlushWingContent())
            }
            return AnyView(
                IslandFlushWingCapsule(side: flushSide ?? .leading) { core }
            )
        }()

        return AnyView(
            filled
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    wingHoverDismissWork?.cancel()
                    wingHoverDismissWork = nil
                    if hovering {
                        if !isWingHovering {
                            AppLog.warn("FocusTimer", "双翼专注悬停：展示操作钮", [
                                "countUp": isCountUp,
                                "overtime": isOvertime,
                                "trailingPinned": trailingWingHover.isActive
                            ])
                        }
                        isWingHovering = true
                    } else if !isWingActionPressing {
                        // 本地 hover 结束一律清旗；仍由 trailingWingHover / pressing 保 morph。
                        // 禁止因 trailingPinned 跳过清理，否则离岛后数字永不回来。
                        let work = DispatchWorkItem {
                            guard !self.isWingActionPressing else { return }
                            self.isWingHovering = false
                            AppLog.warn("FocusTimer", "双翼专注悬停：本地离开，清 isWingHovering", [
                                "trailingPinned": self.trailingWingHover.isActive
                            ])
                        }
                        wingHoverDismissWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
                    }
                }
                .onChange(of: trailingWingHover.isActive) { _, pinned in
                    if !pinned, !isWingActionPressing, !isWingHovering {
                        AppLog.warn("FocusTimer", "双翼专注悬停：收起操作钮", [
                            "countUp": isCountUp
                        ])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(statusLabel)，\(clockText)")
        )
    }

    private func wingIdleRow(spacer: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: IslandFlushWingStyle.iconLabelSpacing) {
                Image(systemName: wingIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(flushAccent)
                    .symbolRenderingMode(.hierarchical)
                Text(clockText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: spacer)
            Circle()
                .fill(Color.white.opacity(isOvertime || isCountUp ? 0.55 : 0.40))
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 悬停右翼：倒计时 `+Nm`+结束；正计时 暂停+结束。整翼热区，勿只点到圆钮才算。
    private var wingActionsRow: some View {
        HStack(spacing: 8) {
            // 原时长区：正计时点按=暂停；倒计时点按仅保 morph（勿空点）。
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isCountUp {
                        pinWingActionsWhilePressing(true)
                        onTogglePause()
                        pinWingActionsWhilePressing(false)
                        AppLog.warn("FocusTimer", "双翼正计时：点按时长区暂停/继续")
                    } else {
                        revealWingActions(reason: "actionsSpacerTap")
                    }
                }
            if isCountUp {
                FocusTimerStandbyPauseButton(
                    isPaused: snapshot.isPaused,
                    action: onTogglePause,
                    onPressingChanged: { pressing in
                        pinWingActionsWhilePressing(pressing)
                    }
                )
                FocusTimerStandbyStopButton(
                    action: onFinishEarly,
                    onPressingChanged: { pressing in
                        pinWingActionsWhilePressing(pressing)
                    }
                )
            } else {
                FocusTimerStandbyExtendButton(
                    minutes: extendStepMinutes,
                    action: onExtend,
                    onPressingChanged: { pressing in
                        pinWingActionsWhilePressing(pressing)
                    }
                )
                FocusTimerStandbyStopButton(
                    action: onFinishEarly,
                    onPressingChanged: { pressing in
                        pinWingActionsWhilePressing(pressing)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func revealWingActions(reason: String) {
        isWingHovering = true
        AppLog.warn("FocusTimer", "双翼专注点按：展开操作钮", [
            "countUp": isCountUp,
            "reason": reason
        ])
    }

    private func pinWingActionsWhilePressing(_ pressing: Bool) {
        wingHoverDismissWork?.cancel()
        wingHoverDismissWork = nil
        isWingActionPressing = pressing
        if pressing {
            isWingHovering = true
        }
    }
}

// MARK: - 2. 选时起钟

private struct FocusTimerPickingView: View {
    let snapshot: FocusTimerSnapshot
    let presets: [FocusTimerPreset]
    let onSelectPreset: (FocusTimerPreset) -> Void
    let onCustomMinutes: (Int) -> Void
    let onStart: () -> Void
    let onStartCountUp: () -> Void

    /// 自定义分钟输入草稿（仅数字）；点播放钮才起钟。
    @State private var customText: String = ""

    private let primaryBlue = Color(red: 0.0, green: 0.35, blue: 0.74)

    var body: some View {
        HStack(spacing: 10) {
            // 预设：深灰胶囊；仅播放三角改蓝，其余保持原样。
            HStack(spacing: 5) {
                ForEach(presets.prefix(3)) { preset in
                    Button {
                        onSelectPreset(preset)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(primaryBlue)
                            Text(L10n.FocusTimer.presetMinutesChip(preset.minutes))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.FocusTimer.presetMinutesChip(preset.minutes))
                }
            }

            // 自定义倒计时：输入 + 蓝播放钮 +「倒计时」文案（与预设之间不画竖线）。
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    FocusTimerMinutesField(text: $customText) { value in
                        onCustomMinutes(value)
                    }
                    .frame(width: 40, height: 22)
                    Text(L10n.FocusTimer.minutesAbbrev)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 2)
                .accessibilityLabel(L10n.FocusTimer.customSessionTitle)

                Button {
                    commitCustomStart()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(L10n.FocusTimer.countdownMode)
                            .font(.system(size: 12, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(primaryBlue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canStartCustom)
                .opacity(canStartCustom ? 1 : 0.45)
                .accessibilityLabel(L10n.FocusTimer.countdownMode)
                .padding(2)
                .padding(.trailing, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )

            pickingDivider

            // 正计时入口：自绘 NSView + IslandDirectHitTarget，整颗 bounds 可点（勿用 NSButton：
            // 播放时标题区常被 hosting/自定义分钟热区抢走，只剩左侧图标能点）。
            // 宽度跟图标+文案自适应，禁止写死导致右侧大片空白。
            FocusTimerCountUpAppKitButton(action: onStartCountUp)
                .frame(height: FocusTimerCountUpButtonLayout.height)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(L10n.FocusTimer.countUpMode)
        }
        .onAppear {
            if customText.isEmpty {
                customText = "\(snapshot.customMinutes)"
            }
            AppLog.debug("FocusTimer", "选时岛已显示", [
                "presetCount": min(3, presets.count),
                "custom": snapshot.customMinutes
            ])
        }
    }

    private var pickingDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 18)
    }

    private var canStartCustom: Bool {
        guard let value = Int(customText), value >= 1 else { return false }
        return true
    }

    private func commitCustomStart() {
        guard let value = Int(customText), value >= 1 else { return }
        onCustomMinutes(min(value, 180))
        onStart()
    }
}

// MARK: - 选时「正计时」AppKit 胶囊

/// 整颗 bounds 可点（图标 +「正计时」三字）。自绘 + `IslandDirectHitTarget`，避免 NSButton
/// 标题区被 hosting 可编辑热区 / 播放悬停抢走。
private struct FocusTimerCountUpAppKitButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> FocusTimerCountUpHitView {
        let view = FocusTimerCountUpHitView()
        view.coordinator = context.coordinator
        view.applyAppearance()
        return view
    }

    func updateNSView(_ view: FocusTimerCountUpHitView, context: Context) {
        context.coordinator.action = action
        view.coordinator = context.coordinator
        view.applyAppearance()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: FocusTimerCountUpHitView,
        context: Context
    ) -> CGSize? {
        FocusTimerCountUpButtonLayout.fittingSize(title: L10n.FocusTimer.countUpMode)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        func fire() {
            AppLog.warn("FocusTimer", "选时：AppKit 正计时起钟")
            action()
        }
    }
}

private final class FocusTimerCountUpHitView: NSView, IslandDirectHitTarget {
    weak var coordinator: FocusTimerCountUpAppKitButton.Coordinator?
    private let fill = NSColor(red: 0.10, green: 0.28, blue: 0.18, alpha: 1)
    private let accent = NSColor(red: 0.45, green: 0.92, blue: 0.58, alpha: 1)
    private var title = L10n.FocusTimer.countUpMode
    private var symbolImage: NSImage?
    private var pressed = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = FocusTimerCountUpButtonLayout.height / 2
        layer?.backgroundColor = fill.cgColor
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAppearance() {
        title = L10n.FocusTimer.countUpMode
        let base = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let palette = base.applying(NSImage.SymbolConfiguration(paletteColors: [accent]))
        symbolImage = NSImage(systemSymbolName: "timer", accessibilityDescription: title)?
            .withSymbolConfiguration(palette)
        toolTip = title
        let bg = pressed ? (fill.blended(withFraction: 0.18, of: .black) ?? fill) : fill
        layer?.backgroundColor = bg.cgColor
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let size = FocusTimerCountUpButtonLayout.fittingSize(title: title)
        return NSSize(width: size.width, height: size.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let hPad = FocusTimerCountUpButtonLayout.horizontalPadding
        let gap = FocusTimerCountUpButtonLayout.iconTitleGap
        let iconSide = FocusTimerCountUpButtonLayout.iconSide
        var x = hPad
        let midY = bounds.midY
        if let symbolImage {
            let iconRect = NSRect(
                x: x,
                y: midY - iconSide / 2,
                width: iconSide,
                height: iconSide
            )
            symbolImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            x = iconRect.maxX + gap
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: FocusTimerCountUpButtonLayout.titleFont,
            .foregroundColor: accent
        ]
        let titleSize = (title as NSString).size(withAttributes: attrs)
        let titleOrigin = NSPoint(x: x, y: midY - titleSize.height / 2)
        (title as NSString).draw(at: titleOrigin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        applyAppearance()
        let local = convert(event.locationInWindow, from: nil)
        AppLog.warn("FocusTimer", "选时正计时 HitView mouseDown", [
            "w": Int(bounds.width),
            "h": Int(bounds.height),
            "localX": Int(local.x),
            "winX": Int(event.locationInWindow.x)
        ])
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        applyAppearance()
        let local = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(local)
        AppLog.warn("FocusTimer", "选时正计时 HitView mouseUp", [
            "inside": inside,
            "localX": Int(local.x),
            "w": Int(bounds.width)
        ])
        if inside {
            coordinator?.fire()
        }
    }
}

/// 岛内自定义分钟：用 AppKit 文本框保证浮层窗也能显示插入光标。
private struct FocusTimerMinutesField: NSViewRepresentable {
    @Binding var text: String
    var onValidMinutes: (Int) -> Void

    private static let textColor = NSColor.white
    private static let caretColor = NSColor.white

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FocusTimerIslandTextField {
        let field = FocusTimerIslandTextField(string: text)
        field.logTag = "自定义分钟"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        field.textColor = Self.textColor
        field.caretColor = Self.caretColor
        field.alignment = .center
        field.delegate = context.coordinator
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.refusesFirstResponder = false
        // 固定理想宽，避免 AppKit 字段热区外溢吃掉右侧「正计时」。
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: FocusTimerIslandTextField, context: Context) {
        // 编辑中勿回写，否则打断 field editor。
        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusTimerMinutesField

        init(_ parent: FocusTimerMinutesField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? FocusTimerIslandTextField else { return }
            IslandInteractionFocus.prepare(window: field.window, reason: "自定义分钟Begin")
            field.applyCaretColor()
            AppLog.debug("FocusTimer", "自定义分钟开始编辑")
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let digits = String(field.stringValue.filter(\.isNumber).prefix(3))
            if field.stringValue != digits {
                field.stringValue = digits
            }
            parent.text = digits
            if let value = Int(digits), value >= 1 {
                parent.onValidMinutes(min(value, 180))
            }
        }
    }
}

/// 单行 NSTextField 在偏高 frame 里默认贴顶；重写 drawing/edit/select rect 做垂直居中。
private final class FocusTimerVerticallyCenteredCell: NSTextFieldCell {
    private func centeredRect(for bounds: NSRect) -> NSRect {
        let ideal = cellSize(forBounds: bounds)
        var rect = bounds
        if rect.height > ideal.height {
            let dy = (rect.height - ideal.height) / 2
            rect.origin.y += dy
            rect.size.height = ideal.height
        }
        return rect
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: super.drawingRect(forBounds: rect))
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredRect(for: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredRect(for: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

/// 允许在非激活 Panel 上首击即聚焦，并露出绿色插入光标。
/// 自定义分钟与终局备注共用同一套，禁止再给终局单独加 refusesFirstResponder（会与 SwiftUI update 抢跑导致点了也输不了）。
private final class FocusTimerIslandTextField: NSTextField {
    var caretColor: NSColor = NSColor(red: 0.325, green: 0.882, blue: 0.435, alpha: 1)
    var logTag: String = "文本框"
    /// 终局备注：使用垂直居中 cell。
    var usesVerticallyCenteredCell = false

    override class var cellClass: AnyClass? {
        get { FocusTimerVerticallyCenteredCell.self }
        set {}
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    convenience init(string: String, verticallyCentered: Bool) {
        self.init(string: string)
        usesVerticallyCenteredCell = verticallyCentered
        if verticallyCentered, !(cell is FocusTimerVerticallyCenteredCell) {
            let next = FocusTimerVerticallyCenteredCell(textCell: string)
            next.isEditable = true
            next.isSelectable = true
            next.isBordered = false
            next.isBezeled = false
            next.drawsBackground = false
            next.font = font
            next.textColor = textColor
            next.alignment = alignment
            next.placeholderAttributedString = placeholderAttributedString
            cell = next
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            applyCaretColor()
            selectText(nil)
            if let editor = currentEditor() as? NSTextView {
                let end = (stringValue as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
            }
            applyCaretColor()
            AppLog.warn("FocusTimer", "\(logTag) 已成为 firstResponder", [
                "key": window?.isKeyWindow ?? false,
                "appActive": NSApp.isActive
            ])
        } else {
            AppLog.warn("FocusTimer", "\(logTag) becomeFirstResponder 失败", [
                "key": window?.isKeyWindow ?? false,
                "appActive": NSApp.isActive,
                "refuses": refusesFirstResponder
            ])
        }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        IslandInteractionFocus.prepare(window: window, reason: "\(logTag)MouseDown")
        let became = window?.makeFirstResponder(self) ?? false
        AppLog.warn("FocusTimer", "\(logTag) mouseDown", [
            "key": window?.isKeyWindow ?? false,
            "firstResponder": became,
            "appActive": NSApp.isActive,
            "frame": "\(Int(bounds.width))x\(Int(bounds.height))"
        ])
        applyCaretColor()
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.window?.firstResponder !== self,
               self.window?.firstResponder !== self.currentEditor()
            {
                IslandInteractionFocus.prepare(window: self.window, reason: "\(self.logTag)Retry")
                let again = self.window?.makeFirstResponder(self) ?? false
                AppLog.warn("FocusTimer", "\(self.logTag) 异步补聚焦", ["ok": again])
            }
            self.applyCaretColor()
            if let editor = self.currentEditor() as? NSTextView {
                let end = (self.stringValue as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
                editor.insertionPointColor = self.caretColor
            }
        }
    }

    func applyCaretColor() {
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = caretColor
        }
    }
}

/// 终局备注宿主：铺满灰底热区；内部字段与自定义分钟同一套（不 refuses）。
private final class FocusTimerNoteFieldHost: NSView, IslandEditableTextHosting {
    let textField: FocusTimerIslandTextField
    var editableField: NSView { textField }

    init(textField: FocusTimerIslandTextField) {
        self.textField = textField
        super.init(frame: .zero)
        wantsLayer = true
        // 明确可点，避免被 SwiftUI 透明层当成「无内容」。
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        // 铺满宿主，垂直居中交给 FocusTimerVerticallyCenteredCell。
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, bounds.contains(point) else { return nil }
        return textField
    }

    override func mouseDown(with event: NSEvent) {
        // 点在左右内边距时仍交给字段，与点在文字区同一路径。
        AppLog.warn("FocusTimer", "终局备注宿主 mouseDown", [
            "w": Int(bounds.width),
            "h": Int(bounds.height)
        ])
        textField.mouseDown(with: event)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: FocusTimerCompletedView.noteRowHeight)
    }

    override func layout() {
        super.layout()
        // 布局完成后打一次尺寸，方便对照 editableHit=nil。
        if bounds.width > 1, bounds.height > 1 {
            AppLog.debug("FocusTimer", "终局备注宿主已布局", [
                "w": Int(bounds.width),
                "h": Int(bounds.height)
            ])
        }
    }
}

/// 终局备注：铺满热区 Host + 与自定义分钟相同的 TextField（无 refuses 抢跑）。
private struct FocusTimerNoteField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    private static let caretColor = NSColor(red: 0.325, green: 0.882, blue: 0.435, alpha: 1)
    private static let textColor = NSColor.white
    private static let placeholderColor = NSColor.white.withAlphaComponent(0.4)

    private static func placeholderAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        return [
            .foregroundColor: placeholderColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .paragraphStyle: paragraph
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FocusTimerNoteFieldHost {
        let field = FocusTimerIslandTextField(string: text, verticallyCentered: true)
        field.logTag = "终局备注"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.textColor = Self.textColor
        field.caretColor = Self.caretColor
        field.alignment = .left
        field.delegate = context.coordinator
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.refusesFirstResponder = false
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: Self.placeholderAttributes()
        )
        // cell 替换后补一次属性，避免 convenience init 时序漏设。
        if let cell = field.cell as? FocusTimerVerticallyCenteredCell {
            cell.font = field.font
            cell.textColor = Self.textColor
            cell.alignment = .left
            cell.placeholderAttributedString = field.placeholderAttributedString
            cell.isScrollable = true
            cell.wraps = false
        }
        let host = FocusTimerNoteFieldHost(textField: field)
        AppLog.warn("FocusTimer", "终局备注字段已创建", [
            "refuses": field.refusesFirstResponder,
            "centeredCell": field.cell is FocusTimerVerticallyCenteredCell
        ])
        return host
    }

    func updateNSView(_ nsView: FocusTimerNoteFieldHost, context: Context) {
        context.coordinator.parent = self
        let field = nsView.textField
        // 编辑中勿回写，否则打断 field editor（与自定义分钟一致）。
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderAttributedString?.string != placeholder {
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: Self.placeholderAttributes()
            )
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusTimerNoteFieldHost, context: Context) -> CGSize? {
        CGSize(width: max(80, proposal.width ?? 240), height: FocusTimerCompletedView.noteRowHeight)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusTimerNoteField

        init(_ parent: FocusTimerNoteField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? FocusTimerIslandTextField else { return }
            IslandInteractionFocus.prepare(window: field.window, reason: "终局备注Begin")
            field.applyCaretColor()
            AppLog.warn("FocusTimer", "终局备注开始编辑")
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - 3. 终局收拢（贴刘海双翼 tip：左勾+时长 · 右备注+回车）

struct FocusTimerCompletedView: View {
    let snapshot: FocusTimerSnapshot
    let onNoteChange: (String) -> Void
    let onSave: () -> Void
    /// 设置样张略收翼宽。
    var compact: Bool = false
    var previewNotchWidth: CGFloat = 110
    @State private var draft: String = ""

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    /// 翼 tip 内容高下限（真岛以刘海高为准，勿再加底距）。
    static let noteRowHeight: CGFloat = 32

    /// 完成勾选圆：与稿面 mint 描边勾一致（约 #7EE3A9）。
    private let green = Color(red: 0.494, green: 0.890, blue: 0.663)
    private let muted = Color.white.opacity(0.45)

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    /// 真岛高=刘海；预览略矮。禁止再叠 chrome 底距把岛顶出刘海下沿。
    private var barHeight: CGFloat {
        compact ? 30 : NotchGeometry.compactPanelHeight(notchHeight: envNotchHeight)
    }

    private var wingWidth: CGFloat {
        compact ? 100 : FocusTimerContentSize.completedWingWidth
    }

    /// 中间空隙 = 刘海宽 + 略加宽，左右内容不要贴着刘海缘。
    private var centerClearWidth: CGFloat {
        notchWidth + (compact ? 4 : FocusTimerContentSize.completedCenterExtra)
    }

    private var totalWidth: CGFloat { wingWidth * 2 + centerClearWidth }

    /// 终局左翼时长文案（正计时墙钟 / 倒计时整分）。
    private var durationLabel: String {
        FocusTimerFormatting.completedDurationLabel(
            elapsedSeconds: snapshot.elapsedSeconds,
            kind: snapshot.kind
        )
    }

    var body: some View {
        // 左右翼贴刘海；壳层 notchWingTip 顶距 0，消灭展开页大顶空。
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth, alignment: .leading)
                .clipped()
            Color.clear
                .frame(width: centerClearWidth)
                .accessibilityHidden(true)
            rightCluster
                .frame(width: wingWidth, alignment: .trailing)
                .clipped()
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(L10n.FocusTimer.completedTitle)，\(durationLabel)"
        )
        .onAppear {
            draft = snapshot.noteDraft
            AppLog.warn("FocusTimer", "终局翼 tip 备注区已显示（默认不聚焦）", [
                "wingW": Int(wingWidth),
                "notchW": Int(notchWidth),
                "center": Int(centerClearWidth),
                "barH": Int(barHeight),
                "notchH": Int(envNotchHeight),
                "duration": durationLabel,
                "kind": snapshot.kind.rawValue,
                "elapsed": snapshot.elapsedSeconds
            ])
        }
    }

    private var leftCluster: some View {
        // 描边勾选圆（checkmark.circle）+ 时长；靠左，图标与数字留间距。
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(green)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)

            Text(durationLabel)
                // 正计时墙钟用等宽数字；倒计时 `Xm` 用默认体，避免「1h 12m」被撑缝。
                .font(.system(
                    size: 14,
                    weight: .semibold,
                    design: snapshot.kind == .countUp ? .monospaced : .default
                ))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightCluster: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)
                .accessibilityHidden(true)
            FocusTimerNoteField(
                text: $draft,
                placeholder: L10n.FocusTimer.notePlaceholder,
                onSubmit: commitSave
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: commitSave) {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.FocusTimer.saveRecord)
            .fixedSize(horizontal: true, vertical: false)
        }
        // 回车钮实心外缘贴齐翼尾时，下圆角弦会吃掉视觉右边距；略收 2pt 与左勾光学对齐。
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 保存时才回写 session，避免逐字 objectWillChange 拆掉 field editor。
    private func commitSave() {
        onNoteChange(draft)
        onSave()
    }
}

// MARK: - 共用控件
// 外观保持原 SwiftUI 稿面；岛上点击稳定性靠「禁每秒缩扩」+ 双翼按下钉 morph，勿再换成 AppKit 改长相。

/// 待命态加时：深灰胶囊 `+5m`（白字）。
private struct FocusTimerStandbyExtendButton: View {
    let minutes: Int
    let action: () -> Void
    var onPressingChanged: ((Bool) -> Void)? = nil

    var body: some View {
        Button(action: action) {
            Text(L10n.FocusTimer.extendChip(minutes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .simultaneousGesture(pressPinGesture)
        .accessibilityLabel(L10n.FocusTimer.extendChip(minutes))
    }

    private var pressPinGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onPressingChanged?(true) }
            .onEnded { _ in onPressingChanged?(false) }
    }
}

/// 待命态结束：深灰圆钮 + 停止方块。
private struct FocusTimerStandbyStopButton: View {
    let action: () -> Void
    var onPressingChanged: ((Bool) -> Void)? = nil
    private let visualSize: CGFloat = 26
    /// 可点外扩；负 padding 收回布局宽，避免过大占位把右圆裁出岛外。
    private let hitPad: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.90))
                .frame(width: visualSize, height: visualSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .padding(hitPad)
                .contentShape(Rectangle())
                .padding(-hitPad)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(pressPinGesture)
        .accessibilityLabel(L10n.FocusTimer.finishEarly)
    }

    private var pressPinGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onPressingChanged?(true) }
            .onEnded { _ in onPressingChanged?(false) }
    }
}

/// 满岛待命左侧进度环（正计时深绿底 + 薄荷标）。
private struct FocusTimerProgressRing: View {
    let progress: Double
    let stroke: Color
    let icon: String
    let iconColor: Color
    var fill: Color? = nil

    var body: some View {
        let d = FocusTimerCompactMetrics.progressRingDiameter
        let line = FocusTimerCompactMetrics.progressRingLineWidth
        ZStack {
            if let fill {
                Circle()
                    .fill(fill)
            }
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(stroke, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: FocusTimerCompactMetrics.progressRingIconPointSize, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: d, height: d)
    }
}

/// 正计时待命：暂停 / 继续圆钮（在结束钮左侧）。
private struct FocusTimerStandbyPauseButton: View {
    let isPaused: Bool
    let action: () -> Void
    var onPressingChanged: ((Bool) -> Void)? = nil
    private let visualSize: CGFloat = 26
    /// 与结束钮同档外扩；禁止只点到 26pt 圆心才算。
    private let hitPad: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.90))
                .frame(width: visualSize, height: visualSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .padding(hitPad)
                .contentShape(Rectangle())
                .padding(-hitPad)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(pressPinGesture)
        .accessibilityLabel(isPaused ? L10n.FocusTimer.resume : L10n.FocusTimer.pause)
    }

    private var pressPinGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onPressingChanged?(true) }
            .onEnded { _ in onPressingChanged?(false) }
    }
}

