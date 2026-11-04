import CoreGraphics
import Foundation
import SwiftUI

/// 灵动岛壳层统一内边距。小组件只排内部内容，勿再加与岛边之间的外圈间距。
enum IslandChrome {
    /// 内容区相对面板左右边。
    static let contentHorizontal: CGFloat = 14
    /// 内容区相对面板底边；与左右边距一致。
    static let contentBottom: CGFloat = contentHorizontal

    /// 左右内边距合计（从内容宽反推面板宽时用）。
    static var horizontalInsetTotal: CGFloat { contentHorizontal * 2 }

    /// 展开态统一顶距：躲开刘海 / 摄像头盲区；各页（含控制台）共用，勿再按 layout 减一截。
    static func expandedTopInset(notchHeight: CGFloat) -> CGFloat {
        max(16, notchHeight + 6)
    }

    /// 瞬时通知顶距（无标题行，略抬高整块内容）。
    static func noticeTopInset(notchHeight: CGFloat) -> CGFloat {
        max(expandedTopInset(notchHeight: notchHeight), (notchHeight * 0.5 + 4) * 2)
    }

    /// 取色左右翼：顶距 0，内容与刘海同高带；左右边距走 `contentHorizontal`。
    static let compactTipTopInset: CGFloat = 0
    static let compactTipBottom: CGFloat = 4

    /// 「已复制」等短提示：躲开刘海后紧贴下方，底距收紧；左右仍用 `contentHorizontal`。
    static func shortTipTopInset(notchHeight: CGFloat) -> CGFloat {
        expandedTopInset(notchHeight: notchHeight)
    }

    static let shortTipBottom: CGFloat = 8
}

/// 展开态面板尺寸由内容测量上报；壳层只负责 clamp，不按 layout 写死宽高。
struct IslandPanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0.5, next.height > 0.5 {
            value = next
        }
    }
}

extension View {
    /// 把自身布局尺寸上报给岛壳（用于自适应面板）。
    func reportIslandPanelSize() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: IslandPanelSizeKey.self, value: geo.size)
            }
        )
    }
}

enum IslandPanelSizing {
    /// 将内容测得尺寸钳到刘海下限与屏宽上限。
    static func clamp(
        _ size: CGSize,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        maxWidth: CGFloat
    ) -> CGSize {
        let minW = max(notchWidth, 1)
        let minH = max(notchHeight, 1)
        let width = min(max(size.width, minW), max(maxWidth, minW))
        let height = max(size.height, minH)
        return CGSize(
            width: NotchGeometry.pixelAlign(width),
            height: NotchGeometry.pixelAlign(height)
        )
    }
}

/// 当前屏刘海高度，供控制台等内容按 chrome 反推画布高。
private struct IslandNotchHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 32
}

private struct IslandNotchWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 160
}

extension EnvironmentValues {
    var islandNotchHeight: CGFloat {
        get { self[IslandNotchHeightKey.self] }
        set { self[IslandNotchHeightKey.self] = newValue }
    }

    var islandNotchWidth: CGFloat {
        get { self[IslandNotchWidthKey.self] }
        set { self[IslandNotchWidthKey.self] = newValue }
    }
}
