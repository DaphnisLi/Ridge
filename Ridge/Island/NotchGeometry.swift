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
    /// 普通展开页高度 = 刘海高 × 此倍率；组合页为 2 倍。
    static let fixedExpandedHeightMultiplier: CGFloat = 3
    /// 控制台混音台：稿面约 660×320，按刘海倍率抬高并设下限。
    static let controlDeckPreferredWidth: CGFloat = 660
    static let controlDeckHeightMultiplier: CGFloat = 8.5
    static let controlDeckMinHeight: CGFloat = 300

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

    /// 普通页展开高度。
    var standardExpandedHeight: CGFloat {
        notchHeight * Self.fixedExpandedHeightMultiplier
    }

    /// 组合页展开高度（普通页的两倍）。
    var comboExpandedHeight: CGFloat {
        standardExpandedHeight * 2
    }

    /// 控制台混音台高度。
    var controlDeckExpandedHeight: CGFloat {
        max(notchHeight * Self.controlDeckHeightMultiplier, Self.controlDeckMinHeight)
    }

    enum ExpandedLayout {
        case standard
        case combo
        case controlDeck
    }

    /// 可见岛面板尺寸。
    func expandedSize(width: CGFloat, combo: Bool = false) -> CGSize {
        expandedSize(width: width, layout: combo ? .combo : .standard)
    }

    func expandedSize(width: CGFloat, layout: ExpandedLayout) -> CGSize {
        let preferredWidth: CGFloat = {
            switch layout {
            case .controlDeck:
                return max(width, Self.controlDeckPreferredWidth)
            case .standard, .combo:
                return width
            }
        }()
        let clamped = min(max(preferredWidth, notchWidth), maxExpandedWidth)
        let height: CGFloat = {
            switch layout {
            case .standard: return standardExpandedHeight
            case .combo: return comboExpandedHeight
            case .controlDeck: return controlDeckExpandedHeight
            }
        }()
        return CGSize(
            width: Self.pixelAlign(clamped),
            height: Self.pixelAlign(height)
        )
    }

    /// 浮层窗口占位：按控制台最大高度，避免翻页裁切。
    var windowSize: CGSize {
        let deck = expandedSize(width: maxExpandedWidth, layout: .controlDeck)
        let combo = expandedSize(width: maxExpandedWidth, layout: .combo)
        return CGSize(
            width: max(deck.width, combo.width),
            height: max(deck.height, combo.height)
        )
    }

    /// 展开态面板在屏幕坐标中的矩形（顶边对齐屏幕顶，水平以刘海居中）。
    func expandedFrameOnScreen(width: CGFloat, layout: ExpandedLayout = .standard) -> CGRect {
        centeredTopFrame(size: expandedSize(width: width, layout: layout))
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
