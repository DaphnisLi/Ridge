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
    /// 番茄倒计时收起待命（左右翼）最小尺寸；加宽让「专注中」与倒计时贴两边。
    static let focusTimerCompactWidth: CGFloat = 348
    static let focusTimerCompactHeight: CGFloat = 44
    /// 正在播放收起待命：左封面歌名、右律动条+时长。
    static let mediaCompactWidth: CGFloat = 300
    static let mediaCompactHeight: CGFloat = 44
    /// 以下常量为各内容模块的**画布参考**（控制台等 GeometryReader 页自报尺寸用），
    /// 不再由壳层按 ExpandedLayout 写死可见面板宽高；展开面板由内容测量 + IslandChrome 撑开。
    static let fixedExpandedHeightMultiplier: CGFloat = 6
    static let noticeHeightMultiplier: CGFloat = 2.65
    /// 控制台混音台：内容模块参考面板约 660×300（含壳层 chrome 时）。
    static let controlDeckPreferredWidth: CGFloat = 660
    static let controlDeckHeightMultiplier: CGFloat = 8.5
    static let controlDeckMinHeight: CGFloat = 300
    /// 电量页：每行最多 3 台，最多 2 行；一行时岛高只撑一行，避免空出第二行。
    static let batteryDeckColumns: Int = 3
    static let batteryDeckMaxRows: Int = 2
    static let controlDeckBatterySingleRowMinHeight: CGFloat = 178
    static let controlDeckBatteryDualRowMinHeight: CGFloat = 300

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

    /// 电量页一行（≤3 台）高度。
    var controlDeckBatterySingleRowHeight: CGFloat {
        max(notchHeight * 5.0, Self.controlDeckBatterySingleRowMinHeight)
    }

    /// 电量页两行（>3 台）高度。
    var controlDeckBatteryDualRowHeight: CGFloat {
        max(
            notchHeight * Self.controlDeckHeightMultiplier,
            Self.controlDeckBatteryDualRowMinHeight
        )
    }

    /// 进程结束等瞬时通知高度（贴刘海）。
    var noticeExpandedHeight: CGFloat {
        max(notchHeight * Self.noticeHeightMultiplier, notchHeight + 34)
    }

    /// 窗口占位与旧调用方仍可能用到的布局枚举；可见面板以内容测量为准。
    enum ExpandedLayout {
        case standard
        case combo
        case controlDeck
        /// 电量外设：仅一行卡片。
        case controlDeckBatterySingle
        /// 电量外设：两行卡片。
        case controlDeckBatteryDual
        case notice
        /// 番茄倒计时内容页。
        case focusTimer
    }

    /// 按已连接外设台数选择电量页岛高（每行 3 台，最多两行）。
    static func controlDeckBatteryLayout(deviceCount: Int) -> ExpandedLayout {
        deviceCount > batteryDeckColumns
            ? .controlDeckBatteryDual
            : .controlDeckBatterySingle
    }

    /// 可见岛面板尺寸。
    func expandedSize(width: CGFloat, combo: Bool = false) -> CGSize {
        expandedSize(width: width, layout: combo ? .combo : .standard)
    }

    func expandedSize(width: CGFloat, layout: ExpandedLayout) -> CGSize {
        let preferredWidth: CGFloat = {
            switch layout {
            case .controlDeck, .controlDeckBatterySingle, .controlDeckBatteryDual:
                return max(width, Self.controlDeckPreferredWidth)
            case .standard, .combo, .notice, .focusTimer:
                return width
            }
        }()
        let clamped = min(preferredWidth, maxExpandedWidth)
        // 仅作窗口占位 / 兜底；真面板尺寸由 IslandContentView 测量。
        let height: CGFloat = {
            switch layout {
            case .standard: return standardExpandedHeight
            case .combo: return comboExpandedHeight
            case .controlDeck: return controlDeckExpandedHeight
            case .controlDeckBatterySingle: return controlDeckBatterySingleRowHeight
            case .controlDeckBatteryDual: return controlDeckBatteryDualRowHeight
            case .notice: return noticeExpandedHeight
            case .focusTimer: return noticeExpandedHeight
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
        let batteryTall = expandedSize(width: maxExpandedWidth, layout: .controlDeckBatteryDual)
        let combo = expandedSize(width: maxExpandedWidth, layout: .combo)
        return CGSize(
            width: max(deck.width, batteryTall.width, combo.width),
            height: max(deck.height, batteryTall.height, combo.height)
        )
    }

    /// 展开态面板在屏幕坐标中的矩形（顶边对齐屏幕顶，水平以刘海居中）。
    func expandedFrameOnScreen(width: CGFloat, layout: ExpandedLayout = .standard) -> CGRect {
        centeredTopFrame(size: expandedSize(width: width, layout: layout))
    }

    /// 按实测面板尺寸贴顶居中（悬停热区 / 可点区与内容撑开一致）。
    func panelFrameOnScreen(size: CGSize) -> CGRect {
        centeredTopFrame(size: size)
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
