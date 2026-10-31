import AppKit

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
}

/// 辅助限制：在未穿透时，仅 `interactiveFrame` 内命中（双保险）。
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
