import AppKit
import CoreGraphics
import Foundation

/// 某块屏幕上的刘海几何（AppKit 屏幕坐标，原点在左下）。
struct NotchGeometry: Equatable {
    let screenID: CGDirectDisplayID
    let screenFrame: CGRect
    /// 刘海在屏幕坐标系中的矩形（贴顶、水平居中）。
    let notchFrame: CGRect
    let hasNotch: Bool

    var notchWidth: CGFloat { notchFrame.width }
    var notchHeight: CGFloat { notchFrame.height }
    var notchCenterX: CGFloat { notchFrame.midX }

    /// 常驻态相对刘海略缩小，避免溢出菜单栏左右。
    static let compactScale: CGFloat = 0.96
    /// 展开高度固定为刘海高 × 此倍率（不可调）。
    static let fixedExpandedHeightMultiplier: CGFloat = 3

    var compactSize: CGSize {
        CGSize(
            width: notchWidth * Self.compactScale,
            height: notchHeight * Self.compactScale
        )
    }

    /// 展开宽度上限：不可超出屏幕，否则左右被裁切。
    var maxExpandedWidth: CGFloat {
        max(notchWidth, screenFrame.width - Self.expandedHorizontalInset * 2)
    }

    static let expandedHorizontalInset: CGFloat = 16

    /// 可见岛面板尺寸（绝对宽度 pt，高度固定）。宽高对齐到 0.5pt。
    func expandedSize(width: CGFloat) -> CGSize {
        let clamped = min(max(width, notchWidth), maxExpandedWidth)
        let height = notchHeight * Self.fixedExpandedHeightMultiplier
        return CGSize(
            width: Self.pixelAlign(clamped),
            height: Self.pixelAlign(height)
        )
    }

    /// 浮层窗口占位：始终用最大展开宽，避免调宽度时窗体与 SwiftUI 面板不同步裁掉圆角。
    var windowSize: CGSize {
        CGSize(
            width: Self.pixelAlign(maxExpandedWidth),
            height: Self.pixelAlign(notchHeight * Self.fixedExpandedHeightMultiplier)
        )
    }

    /// 展开态面板在屏幕坐标中的矩形（顶边对齐屏幕顶，水平以刘海居中）。
    func expandedFrameOnScreen(width: CGFloat) -> CGRect {
        centeredTopFrame(size: expandedSize(width: width))
    }

    /// 窗口在屏幕上的矩形（最大宽度占位）。
    func windowFrameOnScreen() -> CGRect {
        centeredTopFrame(size: windowSize)
    }

    private func centeredTopFrame(size: CGSize) -> CGRect {
        var frame = CGRect(
            x: notchCenterX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if frame.minX < screenFrame.minX + Self.expandedHorizontalInset {
            frame.origin.x = screenFrame.minX + Self.expandedHorizontalInset
        }
        if frame.maxX > screenFrame.maxX - Self.expandedHorizontalInset {
            frame.origin.x = screenFrame.maxX - Self.expandedHorizontalInset - frame.width
        }
        return frame
    }

    static func pixelAlign(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

enum NotchGeometryResolver {
    /// 从 `auxiliaryTopLeft/RightArea` 推算真实刘海宽度；无刘海则返回 nil。
    static func resolve(screen: NSScreen) -> NotchGeometry? {
        let displayID = screen.displayID
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        guard topInset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let notchWidth = right.minX - left.maxX
        guard notchWidth > 40, notchWidth < 400 else {
            AppLog.warn("Notch", "刘海宽度异常，跳过该屏", [
                "display": Int(displayID),
                "width": notchWidth
            ])
            return nil
        }

        let notchHeight = max(topInset, 32)
        let notchFrame = CGRect(
            x: left.maxX,
            y: frame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        return NotchGeometry(
            screenID: displayID,
            screenFrame: frame,
            notchFrame: notchFrame,
            hasNotch: true
        )
    }

    static func notchScreens() -> [(NSScreen, NotchGeometry)] {
        NSScreen.screens.compactMap { screen in
            guard let geometry = resolve(screen: screen) else { return nil }
            return (screen, geometry)
        }
    }

    static func preferred() -> (NSScreen, NotchGeometry)? {
        if let main = NSScreen.main, let geometry = resolve(screen: main) {
            return (main, geometry)
        }
        return notchScreens().first
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
