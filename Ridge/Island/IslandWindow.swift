import AppKit
import SwiftUI

/// 无边框浮层窗：不进 Dock / ⌘Tab（由 LSUIElement + accessory 保证）。
/// 窗体按展开尺寸占位；真正的点击穿透靠 `ignoresMouseEvents`（由控制器按指针位置切换）。
final class IslandWindow: NSPanel {
    var interactiveFrameInWindow: CGRect = .zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func make() -> IslandWindow {
        let window = IslandWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // 固定深色外观，避免系统浅色模式把岛底抬成深灰。
        window.appearance = NSAppearance(named: .darkAqua)
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        // 允许系统截屏 / 录屏拍到灵动岛。
        window.sharingType = .readOnly
        // 默认穿透；指针进入刘海/展开面板后再关闭穿透，避免展开占位挡下方点击。
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        return window
    }

    /// 普通点击只 `makeKey`（nonactivatingPanel 不 activate App），否则 SwiftUI 按钮首击无响应。
    /// 指针离开穿透时由控制器 `resignKey`，避免键盘粘住。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           !ignoresMouseEvents,
           IslandFocusPolicy.shouldMakeKeyOnPlainIslandMouseDown,
           interactiveFrameInWindow.contains(event.locationInWindow),
           !isKeyWindow
        {
            if MenuBarController.shared?.isPointerOverPresentedSettings() == true {
                AppLog.warn("Overlay", "设置窗上跳过岛 makeKey", [
                    "appActive": NSApp.isActive
                ])
            } else {
                IslandInteractionFocus.makeKeyOnly(window: self, reason: "sendEvent.mouseDown")
            }
        }
        super.sendEvent(event)
    }
}

/// 仅在 `interactiveFrame` 内命中；其余返回 nil。
/// 可点区内绝不能返回 nil：透明 SwiftUI 区若放行，点击会漏到被岛盖住的下层页面。
final class IslandHitTestView: NSView {
    var interactiveFrame: CGRect = .zero
    /// 供排查点击：最近一次 mouseDown 的窗内坐标。
    private(set) var lastMouseDownInView: CGPoint?

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMouseDownInView = point
        let hit = hitTest(point)
        let windowIgnores = window?.ignoresMouseEvents ?? true
        AppLog.warn("Overlay", "岛 mouseDown", [
            "x": Int(point.x),
            "y": Int(point.y),
            "inInteractive": interactiveFrame.contains(point),
            "hit": hit.map { String(describing: type(of: $0)) } ?? "nil",
            "clickThrough": windowIgnores,
            "ix": Int(interactiveFrame.origin.x),
            "iy": Int(interactiveFrame.origin.y),
            "iw": Int(interactiveFrame.width),
            "ih": Int(interactiveFrame.height),
            "controlDeck": WidgetRuntime.shared.isControlDeckPage
        ])
        super.mouseDown(with: event)
    }
}

/// 横向翻页拖拽：位移不足或偏竖直时失败，避免抢走混音台按钮点击。
final class HorizontalPagePanRecognizer: NSPanGestureRecognizer {
    private let recognizeDistance: CGFloat = 12

    override func mouseDragged(with event: NSEvent) {
        if state == .possible {
            guard let view else {
                state = .failed
                return
            }
            let t = translation(in: view)
            let distance = hypot(t.x, t.y)
            if distance < recognizeDistance {
                return
            }
            if abs(t.x) <= abs(t.y) {
                state = .failed
                return
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if state == .possible {
            state = .failed
        }
        super.mouseUp(with: event)
    }
}

/// AppKit 文本宿主：命中容器即视为命中内部可编辑字段（避免 SwiftUI padding 漏点）。
protocol IslandEditableTextHosting: AnyObject {
    var editableField: NSView { get }
}

/// 岛上焦点：文本框才 activate；普通点击只 makeKey（供 SwiftUI 按钮）。
enum IslandInteractionFocus {
    /// 文本输入：临时升 regular + activate + makeKey。
    static func prepare(window: NSWindow?, reason: String) {
        var promoted = false
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            promoted = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        AppLog.warn("Overlay", "文本输入焦点就绪", [
            "reason": reason,
            "promoted": promoted,
            "appActive": NSApp.isActive,
            "key": window?.isKeyWindow ?? false
        ])
    }

    /// 普通点击：只让岛成为 key，不 `activate` 抢前台。
    static func makeKeyOnly(window: NSWindow?, reason: String) {
        guard let window else { return }
        guard !window.isKeyWindow else { return }
        window.makeKeyAndOrderFront(nil)
        AppLog.warn("Overlay", "岛 makeKey（不 activate）", [
            "reason": reason,
            "key": window.isKeyWindow,
            "appActive": NSApp.isActive
        ])
    }

    /// 当前岛窗是否正在编辑 AppKit 文本（用于挡住误收起）。
    static func isEditing(in window: NSWindow?) -> Bool {
        guard let fr = window?.firstResponder else { return false }
        return fr is NSTextField || fr is NSTextView
    }
}

/// 承接触控板横滑（备份路径；主路径在 IslandController 的 scroll 监视器）。
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onHorizontalPageSwipe: ((Int) -> Void)?
    private var scrollAccumX: CGFloat = 0

    /// nonactivatingPanel 不抢前台；必须允许首击直达 SwiftUI 按钮，否则「点一下没反应」。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 1) 可编辑字段优先。
    /// 2) AppKit 控件（会议「进入」NSButton 等）必须直达，否则 hosting 吞掉 mouseDown。
    /// 3) 其余仍由本 view 接手（acceptsFirstMouse + makeKey），避免透明区漏点。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let editable = editableSubview(at: point) {
            return editable
        }
        if let systemHit = super.hitTest(point) {
            var cursor: NSView? = systemHit
            while let cur = cursor, cur !== self {
                if cur is NSControl {
                    return cur
                }
                cursor = cur.superview
            }
        }
        return self
    }

    /// 从某命中视图向上找可编辑控件 / 文本宿主。
    private func nearestEditable(from view: NSView?) -> NSView? {
        var cursor: NSView? = view
        while let cur = cursor {
            if let host = cur as? IslandEditableTextHosting {
                return host.editableField
            }
            if cur is NSTextField || cur is NSTextView {
                return cur
            }
            cursor = cur.superview
        }
        return nil
    }

    /// 在 point（本 view 坐标）下寻找可编辑子视图；宿主容器命中也算。
    private func editableSubview(at point: NSPoint) -> NSView? {
        // 先走系统命中：SwiftUI 包一层时，仅靠自建 walk 会漏掉终局备注 Host（日志 editableHit=nil）。
        if let systemHit = super.hitTest(point),
           let editable = nearestEditable(from: systemHit),
           editable !== self
        {
            return editable
        }

        var match: NSView?
        var nearestHost: (view: NSView, distance: CGFloat)?
        func walk(_ view: NSView) {
            for sub in view.subviews {
                walk(sub)
                let frameInSelf = sub.convert(sub.bounds, to: self)
                // 零尺寸代表尚未布局完，跳过。
                guard frameInSelf.width > 1, frameInSelf.height > 1 else { continue }
                if let host = sub as? IslandEditableTextHosting {
                    // 仅番茄备注等 Host 扩热区；普通搜索框禁止外扩，否则会吃掉右侧按钮点击。
                    let expanded = frameInSelf.insetBy(dx: -6, dy: -6)
                    if expanded.contains(point) {
                        match = host.editableField
                    } else {
                        let dx = max(0, max(frameInSelf.minX - point.x, point.x - frameInSelf.maxX))
                        let dy = max(0, max(frameInSelf.minY - point.y, point.y - frameInSelf.maxY))
                        let distance = hypot(dx, dy)
                        if nearestHost == nil || distance < nearestHost!.distance {
                            nearestHost = (host.editableField, distance)
                        }
                    }
                } else if (sub is NSTextField || sub is NSTextView), frameInSelf.contains(point) {
                    // 剪贴板搜索宿主：热区以宿主为准，避免 AppKit 字段热区外溢。
                    if let host = sub.superview as? ShelfClipboardSearchHost {
                        let hostFrame = host.convert(host.bounds, to: self)
                        if hostFrame.contains(point) {
                            match = sub
                        }
                    } else {
                        match = sub
                    }
                }
            }
        }
        walk(self)
        if let match { return match }
        // 终局备注热区偶发与点击差几像素：仅对 IslandEditableTextHosting 兜底。
        if let nearestHost, nearestHost.distance <= 24 {
            return nearestHost.view
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let editable = editableSubview(at: point)
        // 文本框：activate；普通按钮：只 makeKey，否则 SwiftUI 首击无响应。
        if let editable {
            IslandInteractionFocus.prepare(window: window, reason: "hostingMouseDown.editable")
            AppLog.warn("Overlay", "hosting mouseDown 文本", [
                "x": Int(point.x),
                "y": Int(point.y),
                "key": window?.isKeyWindow ?? false,
                "activeApp": NSApp.isActive,
                "editableHit": String(describing: type(of: editable))
            ])
            editable.mouseDown(with: event)
            return
        }
        if IslandFocusPolicy.shouldActivateAppOnPlainIslandMouseDown {
            IslandInteractionFocus.prepare(window: window, reason: "hostingMouseDown.plain")
        } else if IslandFocusPolicy.shouldMakeKeyOnPlainIslandMouseDown {
            IslandInteractionFocus.makeKeyOnly(window: window, reason: "hostingMouseDown.plain")
        }
        AppLog.warn("Overlay", "hosting mouseDown", [
            "x": Int(point.x),
            "y": Int(point.y),
            "key": window?.isKeyWindow ?? false,
            "activeApp": NSApp.isActive,
            "controlDeck": WidgetRuntime.shared.isControlDeckPage,
            "hostW": Int(bounds.width),
            "hostH": Int(bounds.height)
        ])
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.momentumPhase != [] && event.momentumPhase != .began {
            scrollAccumX = 0
            super.scrollWheel(with: event)
            return
        }

        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        if abs(dx) > abs(dy), abs(dx) > 0.05 {
            scrollAccumX += dx
            if scrollAccumX <= -10 {
                AppLog.debug("Overlay", "hosting 触控板横滑翻页", ["offset": 1, "accum": scrollAccumX])
                onHorizontalPageSwipe?(1)
                scrollAccumX = 0
            } else if scrollAccumX >= 10 {
                AppLog.debug("Overlay", "hosting 触控板横滑翻页", ["offset": -1, "accum": scrollAccumX])
                onHorizontalPageSwipe?(-1)
                scrollAccumX = 0
            }
            return
        }
        scrollAccumX = 0
        super.scrollWheel(with: event)
    }
}
