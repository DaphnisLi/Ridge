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
        window.sharingType = .none
        // 默认穿透；指针进入刘海/展开面板后再关闭穿透，避免展开占位挡下方点击。
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        return window
    }

    /// 点击前若丢了 key，先夺回再派发，否则 SwiftUI 手势不吃这次 mouseDown。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           !ignoresMouseEvents,
           interactiveFrameInWindow.contains(event.locationInWindow),
           !isKeyWindow {
            makeKeyAndOrderFront(nil)
            AppLog.info("Overlay", "mouseDown 前补 makeKey", [
                "key": isKeyWindow,
                "appActive": NSApp.isActive
            ])
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
        AppLog.info("Overlay", "岛 mouseDown", [
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

/// 承接触控板横滑（备份路径；主路径在 IslandController 的 scroll 监视器）。
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onHorizontalPageSwipe: ((Int) -> Void)?
    private var scrollAccumX: CGFloat = 0

    /// nonactivatingPanel 不抢前台；必须允许首击直达 SwiftUI 按钮，否则「点一下没反应」。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 1) 别的 App 在前台时，SwiftUI 子视图不吃 first mouse → 由本 view 接手。
    /// 2) 透明/无控件区域 `super.hitTest` 会 nil → 也必须接手，否则点击漏到下层页面。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 兜底：若悬停激活竞态失败，首击前再拉一次前台（仍保持 accessory）。
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKey()
            AppLog.warn("Overlay", "hosting mouseDown 时 App 仍未激活，已补激活", [
                "x": Int(point.x),
                "y": Int(point.y)
            ])
        } else if window?.isKeyWindow != true {
            window?.makeKey()
        }
        AppLog.info("Overlay", "hosting mouseDown", [
            "x": Int(point.x),
            "y": Int(point.y),
            "key": window?.isKeyWindow ?? false,
            "activeApp": NSApp.isActive,
            "controlDeck": WidgetRuntime.shared.isControlDeckPage
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
