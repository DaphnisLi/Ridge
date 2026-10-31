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

/// 仅在 `interactiveFrame` 内命中；其余返回 nil，事件落到下方 App。
final class IslandHitTestView: NSView {
    var interactiveFrame: CGRect = .zero

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 承接触控板横滑（备份路径；主路径在 IslandController 的 scroll 监视器）。
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onHorizontalPageSwipe: ((Int) -> Void)?
    private var scrollAccumX: CGFloat = 0

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
