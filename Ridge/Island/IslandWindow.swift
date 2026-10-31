import AppKit

/// 无边框浮层窗：不进 Dock / ⌘Tab（由 LSUIElement + accessory 保证），点击穿透由 contentView hitTest 控制。
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
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        return window
    }
}

/// 仅在 `interactiveFrame` 内命中；其余返回 nil，事件落到下方 App。
/// 悬停展开不依赖 trackingArea（避免改尺寸时抖动）。
final class IslandHitTestView: NSView {
    var interactiveFrame: CGRect = .zero

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
