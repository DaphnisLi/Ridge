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
    /// 设置预览无硬件刘海：翼 tip 顶距为 0，预览只留底距。
    static var completedPreviewTopInset: CGFloat { 0 }
    static var completedBottomInset: CGFloat { IslandChrome.compactTipBottom }

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
            return IslandChrome.preparedWingTipPanelSize(
                notchWidth: notchWidth + completedCenterExtra,
                notchHeight: notchHeight,
                wingWidth: completedWingWidth
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
    @State private var wingHoverDismissWork: DispatchWorkItem?

    private var isOvertime: Bool { snapshot.phase == .overtime }
    private var isCountUp: Bool { snapshot.isCountUp }
    /// 双翼闲时小标：正计时 timer / 加时闹钟 / 倒计时沙漏。
    private var wingIcon: String {
        if isCountUp { return "timer" }
        return isOvertime ? "alarm.fill" : "hourglass"
    }
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
        // 倒计时：左剩余，右 +Nm / 停止；正计时：左已过，右暂停 / 停止。无进度环（双翼仍用小标）。
        // 左右 padding 写在内容内，外层勿再叠，否则固定岛宽会被吃掉导致芯片裁切。
        HStack(spacing: 0) {
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
        .padding(.horizontal, NotchGeometry.focusTimerStandbyHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // 相对垂直居中再略下移，加大与顶边的空隙。
        .padding(.top, FocusTimerCompactMetrics.standbyTopNudge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(statusLabel)，\(clockText)")
    }

    private func wingLeadContent(bare: Bool) -> some View {
        // 双槽半块：闲时外图标|时长|点；悬停 morph 操作钮（勿开媒体大面板，由 Controller 排除右翼）。
        // contentShape / onHover 必须在铺满翼槽之后，否则左右 padding / Spacer 一移就收钮。
        let spacer = bare
            ? IslandFlushWingStyle.bareContentSpacerMin
            : CGFloat(4)
        let core = ZStack {
            wingIdleRow(spacer: spacer)
                .opacity(isWingHovering ? 0 : 1)
                .scaleEffect(isWingHovering ? 0.96 : 1)
                .allowsHitTesting(!isWingHovering)
            wingActionsRow
                .opacity(isWingHovering ? 1 : 0)
                .scaleEffect(isWingHovering ? 1 : 0.96)
                .allowsHitTesting(isWingHovering)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.14), value: isWingHovering)

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
                .contentShape(Rectangle())
                .onHover { hovering in
                    wingHoverDismissWork?.cancel()
                    wingHoverDismissWork = nil
                    if hovering {
                        if !isWingHovering {
                            AppLog.debug("FocusTimer", "双翼专注悬停：展示操作钮", [
                                "countUp": isCountUp,
                                "overtime": isOvertime
                            ])
                        }
                        isWingHovering = true
                    } else {
                        // 短宽限：morph / 点按瞬间出界或贴边穿透抖动不立刻收钮。
                        let work = DispatchWorkItem {
                            isWingHovering = false
                            AppLog.debug("FocusTimer", "双翼专注悬停：收起操作钮")
                        }
                        wingHoverDismissWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
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
    }

    /// 悬停右翼：倒计时 `+Nm`+结束；正计时 暂停+结束。
    private var wingActionsRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
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
    /// 正计时胶囊：深绿底 + 薄荷绿字/标。
    private let countUpFill = Color(red: 0.10, green: 0.28, blue: 0.18)
    private let countUpAccent = Color(red: 0.45, green: 0.92, blue: 0.58)

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

            // 正计时入口（深绿胶囊）。
            Button {
                onStartCountUp()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.FocusTimer.countUpMode)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(countUpAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(countUpFill)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.FocusTimer.countUpMode)
        }
        .onAppear {
            if customText.isEmpty {
                customText = "\(snapshot.customMinutes)"
            }
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

    /// 翼 tip 内容高（与刘海同量级）。
    static let noteRowHeight: CGFloat = 32

    /// 完成勾选圆：与稿面 mint 描边勾一致（约 #7EE3A9）。
    private let green = Color(red: 0.494, green: 0.890, blue: 0.663)
    private let muted = Color.white.opacity(0.45)

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        compact ? 30 : max(envNotchHeight, 32)
    }

    private var wingWidth: CGFloat {
        compact ? 100 : FocusTimerContentSize.completedWingWidth
    }

    /// 中间空隙 = 刘海宽 + 略加宽，左右内容不要贴着刘海缘。
    private var centerClearWidth: CGFloat {
        notchWidth + (compact ? 4 : FocusTimerContentSize.completedCenterExtra)
    }

    private var totalWidth: CGFloat { wingWidth * 2 + centerClearWidth }

    /// 主时长：实际已过分钟（至少 1）；岛上不展示加时括号旁注。
    private var actualFocusMinutes: Int {
        max(1, (snapshot.elapsedSeconds + 59) / 60)
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
            "\(L10n.FocusTimer.completedTitle)，\(FocusTimerFormatting.compactDuration(actualFocusMinutes))"
        )
        .onAppear {
            draft = snapshot.noteDraft
            AppLog.warn("FocusTimer", "终局翼 tip 备注区已显示（默认不聚焦）", [
                "wingW": Int(wingWidth),
                "notchW": Int(notchWidth),
                "center": Int(centerClearWidth),
                "barH": Int(barHeight)
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

            Text(FocusTimerFormatting.compactDuration(actualFocusMinutes))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
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
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 保存时才回写 session，避免逐字 objectWillChange 拆掉 field editor。
    private func commitSave() {
        onNoteChange(draft)
        onSave()
    }
}

// MARK: - 共用控件

/// 待命态加时：深灰胶囊 `+5m`（白字）。
private struct FocusTimerStandbyExtendButton: View {
    let minutes: Int
    let action: () -> Void

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
        .accessibilityLabel(L10n.FocusTimer.extendChip(minutes))
    }
}

/// 待命态结束：深灰圆钮 + 停止方块。
private struct FocusTimerStandbyStopButton: View {
    let action: () -> Void
    /// 可视圆；可点区更大，半岛小圆不易点空。
    private let visualSize: CGFloat = 26
    private let hitSize: CGFloat = 44

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
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.FocusTimer.finishEarly)
    }
}

/// 正计时待命：暂停 / 继续圆钮（在结束钮左侧）。
private struct FocusTimerStandbyPauseButton: View {
    let isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.90))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? L10n.FocusTimer.resume : L10n.FocusTimer.pause)
    }
}

