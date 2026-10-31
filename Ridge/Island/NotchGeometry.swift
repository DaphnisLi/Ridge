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
    /// 展开倍率默认值（与 IslandSettings.Defaults 对齐）。
    static let defaultExpandedWidthMultiplier: CGFloat = 2
    static let defaultExpandedHeightMultiplier: CGFloat = 3

    var compactSize: CGSize {
        CGSize(
            width: notchWidth * Self.compactScale,
            height: notchHeight * Self.compactScale
        )
    }

    func expandedSize(widthScale: CGFloat, heightScale: CGFloat) -> CGSize {
        CGSize(
            width: notchWidth * widthScale,
            height: notchHeight * heightScale
        )
    }

    /// 展开态面板在屏幕坐标中的矩形（顶边对齐屏幕顶，水平以刘海居中）。
    func expandedFrameOnScreen(widthScale: CGFloat, heightScale: CGFloat) -> CGRect {
        let size = expandedSize(widthScale: widthScale, heightScale: heightScale)
        return CGRect(
            x: notchCenterX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
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
