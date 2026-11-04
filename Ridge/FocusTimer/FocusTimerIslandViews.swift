import AppKit
import SwiftUI

/// 番茄面板下限：选时 / 进行中 / 顺延走内容 `fixedSize` + IslandChrome；
/// 仅终局锁最小宽高，防止 Preference 矮框裁掉备注。
enum FocusTimerContentSize {
    /// 终局备注行需要的内容宽；其它态不锁宽，由内容撑开。
    static let completedContentWidth: CGFloat = 480

    static func minimumContentHeight(phase: FocusTimerPhase) -> CGFloat {
        switch phase {
        case .picking, .running, .overtime:
            return 28
        case .completed:
            // 标题行 ≈26 + 分隔 + 备注行 36；贴内容高度，底边不再虚空。
            return 68
        }
    }

    /// 展开首帧 / Preference 下限（宽仅终局抬升；其它态宽交给测量）。
    static func panelSize(phase: FocusTimerPhase, notchHeight: CGFloat) -> CGSize {
        let height = IslandChrome.expandedTopInset(notchHeight: notchHeight)
            + minimumContentHeight(phase: phase)
            + IslandChrome.contentBottom
        let width: CGFloat = {
            switch phase {
            case .completed:
                return completedContentWidth + IslandChrome.horizontalInsetTotal
            case .picking, .running, .overtime:
                // 仅作展开占位种子；真正宽度由 Preference 内容测量，可小于此值。
                return 360 + IslandChrome.horizontalInsetTotal
            }
        }()
        return CGSize(width: width, height: height)
    }

    /// Preference 是否应抬升宽度（仅终局）。
    static func shouldFloorWidth(phase: FocusTimerPhase) -> Bool {
        phase == .completed
    }
}

/// 岛面番茄倒计时：按 phase 渲染五态；预览可注入 snapshot。
struct FocusTimerIslandCardView: View {
    let snapshot: FocusTimerSnapshot
    var isExpanded: Bool = true
    var onSelectPreset: (FocusTimerPreset) -> Void = { _ in }
    var onCustomMinutes: (Int) -> Void = { _ in }
    var onStart: () -> Void = {}
    var onExtend: () -> Void = {}
    var onFinishEarly: () -> Void = {}
    var onNoteChange: (String) -> Void = { _ in }
    var onSave: () -> Void = {}
    var presets: [FocusTimerPreset] = FocusTimerPreset.defaults
    var extendStepMinutes: Int = 5

    var body: some View {
        Group {
            if !isExpanded, snapshot.phase == .running || snapshot.phase == .overtime {
                FocusTimerStandbyView(snapshot: snapshot)
            } else if snapshot.phase == .completed {
                // 只锁宽；高度跟内容走，避免虚高把底边距撑大。
                phaseBody
                    .frame(width: FocusTimerContentSize.completedContentWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 选时 / 进行中 / 顺延：内容固有尺寸，左右底边距走 IslandChrome，勿再锁死宽。
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
                onStart: onStart
            )
        case .running:
            FocusTimerRunningView(
                snapshot: snapshot,
                extendStepMinutes: extendStepMinutes,
                onExtend: onExtend,
                onFinishEarly: onFinishEarly
            )
        case .overtime:
            FocusTimerOvertimeView(
                snapshot: snapshot,
                extendStepMinutes: extendStepMinutes,
                onExtend: onExtend,
                onFinish: onFinishEarly
            )
        case .completed:
            FocusTimerCompletedView(
                snapshot: snapshot,
                onNoteChange: onNoteChange,
                onSave: onSave
            )
        }
    }

    /// 设置预览：按态切换样张。
    static func previewSample(phase: FocusTimerPhase = .running, compact: Bool = false) -> some View {
        let snap: FocusTimerSnapshot = {
            switch phase {
            case .picking: return .pickingPreview
            case .running: return compact ? .runningStandbyPreview : .runningExpandedPreview
            case .overtime: return .overtimePreview
            case .completed: return .completedPreview
            }
        }()
        return FocusTimerIslandCardView(
            snapshot: snap,
            isExpanded: !compact || phase == .picking || phase == .completed,
            presets: FocusTimerPreset.defaults,
            extendStepMinutes: 5
        )
    }
}

// MARK: - 1. 标准待命（收起）

struct FocusTimerStandbyView: View {
    let snapshot: FocusTimerSnapshot

    private var isOvertime: Bool { snapshot.phase == .overtime }
    private var ringColor: Color {
        isOvertime
            ? Color(red: 0.96, green: 0.62, blue: 0.04)
            : Color(red: 0.325, green: 0.882, blue: 0.435)
    }

    var body: some View {
        // 左右翼贴边拉开，勿挤在胶囊中段。
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                FocusTimerProgressRing(
                    progress: snapshot.progress,
                    stroke: ringColor,
                    icon: isOvertime ? "alarm.fill" : "timer",
                    iconColor: ringColor
                )
                Text(isOvertime ? L10n.FocusTimer.overtimeBadge : L10n.FocusTimer.focusing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Text(
                    isOvertime
                        ? "+\(FocusTimerFormatting.clock(snapshot.remainingSeconds))"
                        : FocusTimerFormatting.clock(snapshot.remainingSeconds)
                )
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOvertime ? Color(red: 1.0, green: 0.75, blue: 0.35) : .white)
                Circle()
                    .fill(ringColor)
                    .frame(width: 8, height: 8)
                    .opacity(0.95)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. 选时起钟

private struct FocusTimerPickingView: View {
    let snapshot: FocusTimerSnapshot
    let presets: [FocusTimerPreset]
    let onSelectPreset: (FocusTimerPreset) -> Void
    let onCustomMinutes: (Int) -> Void
    let onStart: () -> Void

    /// 自定义分钟输入草稿（仅数字）；点「开始计时」才起钟。
    @State private var customText: String = ""

    private let playGreen = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let primaryBlue = Color(red: 0.0, green: 0.35, blue: 0.74)

    var body: some View {
        HStack(spacing: 10) {
            // 预设：播放图标 + 分钟，一点即起。
            HStack(spacing: 5) {
                ForEach(presets.prefix(4)) { preset in
                    Button {
                        onSelectPreset(preset)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(playGreen)
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

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 18)

            // 自定义：输入框与「开始计时」并成一块。
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
                        Text(L10n.FocusTimer.start)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(primaryBlue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canStartCustom)
                .opacity(canStartCustom ? 1 : 0.45)
                .padding(2)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            if customText.isEmpty {
                customText = "\(snapshot.customMinutes)"
            }
        }
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

    private static let caretColor = NSColor(red: 0.325, green: 0.882, blue: 0.435, alpha: 1)

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
        field.textColor = Self.caretColor
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

// MARK: - 3. 计时进行中（展开）

private struct FocusTimerRunningView: View {
    let snapshot: FocusTimerSnapshot
    let extendStepMinutes: Int
    let onExtend: () -> Void
    let onFinishEarly: () -> Void

    private let green = Color(red: 0.325, green: 0.882, blue: 0.435)

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                FocusTimerProgressRing(
                    progress: snapshot.progress,
                    stroke: Color(red: 0.0, green: 0.44, blue: 0.92),
                    icon: "hourglass",
                    iconColor: Color(red: 0.68, green: 0.78, blue: 1.0)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.FocusTimer.plannedLabel(snapshot.plannedMinutes))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(L10n.FocusTimer.elapsedLabel(FocusTimerFormatting.clock(snapshot.elapsedSeconds)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Text(L10n.FocusTimer.remaining)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(FocusTimerFormatting.clock(snapshot.remainingSeconds))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Circle()
                    .fill(green)
                    .frame(width: 8, height: 8)
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                FocusTimerSolidExtendButton(minutes: extendStepMinutes, action: onExtend)
                FocusTimerStopButton(action: onFinishEarly)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }
}

// MARK: - 4. 顺延加时

private struct FocusTimerOvertimeView: View {
    let snapshot: FocusTimerSnapshot
    let extendStepMinutes: Int
    let onExtend: () -> Void
    let onFinish: () -> Void

    private let amber = Color(red: 0.98, green: 0.75, blue: 0.14)
    private let amberText = Color(red: 1.0, green: 0.75, blue: 0.35)

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(amber.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(amber)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.FocusTimer.overtimeAdded(snapshot.overtimeMinutes))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(amberText)
                    Text(L10n.FocusTimer.totalPlanned(snapshot.plannedMinutes + snapshot.overtimeMinutes))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Text(L10n.FocusTimer.remaining)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.90, blue: 0.70).opacity(0.7))
                Text("+\(FocusTimerFormatting.clock(snapshot.remainingSeconds))")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(amberText)
                Circle()
                    .fill(amber)
                    .frame(width: 8, height: 8)
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                FocusTimerSolidExtendButton(minutes: extendStepMinutes, action: onExtend)
                FocusTimerStopButton(action: onFinish)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }
}

// MARK: - 5. 终局收拢

private struct FocusTimerCompletedView: View {
    let snapshot: FocusTimerSnapshot
    let onNoteChange: (String) -> Void
    let onSave: () -> Void
    @State private var draft: String = ""

    /// 备注行 /「完成命名」统一高度（与早期稿面灰底高度一致）。
    static let noteRowHeight: CGFloat = 36

    private let green = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let amberText = Color(red: 1.0, green: 0.75, blue: 0.35)

    /// 总专注展示实际已过分钟。
    private var actualFocusMinutes: Int {
        max(1, snapshot.elapsedSeconds / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(green)
                    Text(L10n.FocusTimer.completedTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(green)
                            .frame(width: 6, height: 6)
                        Text(L10n.FocusTimer.autoArchivedBadge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(green.opacity(0.15))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(green.opacity(0.22), lineWidth: 1)
                            )
                    )
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(L10n.FocusTimer.baseMinutes(snapshot.plannedMinutes))
                        .foregroundStyle(Color.white.opacity(0.45))
                    if snapshot.overtimeMinutes > 0 {
                        Text("+")
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(L10n.FocusTimer.overtimeMinutesLabel(snapshot.overtimeMinutes))
                            .fontWeight(.bold)
                            .foregroundStyle(amberText)
                        Text("=")
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Text(L10n.FocusTimer.totalFocus(actualFocusMinutes))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(green)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)
            }

            // 稿面：左侧输入框吃满剩余宽度；右侧「完成命名」按内容收窄，勿均分。
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    HStack(alignment: .center, spacing: 8) {
                        FocusTimerNoteField(
                            text: $draft,
                            placeholder: L10n.FocusTimer.notePlaceholder,
                            onSubmit: commitSave
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(alignment: .center, spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(green)
                                Text(L10n.FocusTimer.defaultTimeNameHint)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.40))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: true)
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.noteRowHeight)
                .layoutPriority(1)

                Button(action: commitSave) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(green)
                            Text(L10n.FocusTimer.saveRecord)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: Self.noteRowHeight)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
        }
        // 勿 maxHeight: .infinity，否则吃满虚高面板，底边空一大截。
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            draft = snapshot.noteDraft
            // 不主动 makeFirstResponder；离开岛时 collapse 会卸焦。勿再用 refusesFirstResponder。
            AppLog.warn("FocusTimer", "终局备注区已显示（默认不聚焦）")
        }
    }

    /// 保存时才回写 session，避免逐字 objectWillChange 拆掉 field editor。
    private func commitSave() {
        onNoteChange(draft)
        onSave()
    }
}

// MARK: - 共用控件

/// 实心琥珀加时：`+5m`。
private struct FocusTimerSolidExtendButton: View {
    let minutes: Int
    let action: () -> Void

    private let amber = Color(red: 0.98, green: 0.75, blue: 0.14)

    var body: some View {
        Button(action: action) {
            Text(L10n.FocusTimer.extendChip(minutes))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(amber)
                        .shadow(color: amber.opacity(0.35), radius: 4, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 结束：停止图标 +「结束」。
private struct FocusTimerStopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(L10n.FocusTimer.finishEarly)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Ring

private struct FocusTimerProgressRing: View {
    let progress: Double
    let stroke: Color
    let icon: String
    let iconColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(stroke, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: 24, height: 24)
    }
}
