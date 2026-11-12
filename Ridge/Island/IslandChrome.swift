import CoreGraphics
import Foundation
import SwiftUI

/// 灵动岛壳层统一内边距。小组件 / 通知卡只排内部内容，**禁止**再加与岛边之间的外圈间距。
/// 下边距过大的常见原因：内容根视图又写了 `.padding(.vertical)` 或照搬 HTML `py-*`，与 `contentBottom` 叠层。
///
/// 左右 / 底边是**固定令牌**；改数值须同步 `RidgeTests`（`island-chrome-double-padding`）。
enum IslandChrome {
    /// 内容区相对面板左右边（展开页 / tip / 短提示统一）。
    static let contentHorizontal: CGFloat = 14
    /// 内容区相对面板底边；与左右边距一致。
    static let contentBottom: CGFloat = contentHorizontal

    /// 左右内边距合计（从内容宽反推面板宽时用）。
    static var horizontalInsetTotal: CGFloat { contentHorizontal * 2 }

    /// 展开态统一顶距：躲开刘海 / 摄像头盲区；各页（含控制台）共用，勿再按 layout 减一截。
    static func expandedTopInset(notchHeight: CGFloat) -> CGFloat {
        max(16, notchHeight + 6)
    }

    /// 设置预览用：真岛顶距含刘海盲区，贴顶时被硬件挡住；预览无刘海，若照搬会留下大块空黑、整体发暗。
    /// 只保留「刘海下沿 → 内容」的可见间隙，左右/底与卡片样式仍与真岛一致。
    static func previewExpandedVisibleTopInset(notchHeight: CGFloat = 32) -> CGFloat {
        max(contentBottom, expandedTopInset(notchHeight: notchHeight) - notchHeight)
    }

    /// 瞬时通知顶距（无标题行，略抬高整块内容）。
    static func noticeTopInset(notchHeight: CGFloat) -> CGFloat {
        max(expandedTopInset(notchHeight: notchHeight), (notchHeight * 0.5 + 4) * 2)
    }

    /// 遗留左右翼 tip 令牌（已无业务使用；测试仍锁定数值防回退）。
    static let compactTipTopInset: CGFloat = 0
    static let compactTipBottom: CGFloat = 4

    /// 矮胶囊短提示（「已复制」等）：躲开刘海后落在正下方。取色 / 框选 / 会议 / 久坐走翼 tip。
    static func shortTipTopInset(notchHeight: CGFloat) -> CGFloat {
        max(10, notchHeight)
    }

    /// 短提示底距：仍明显小于展开页默认 contentBottom（14）。
    static let shortTipBottom: CGFloat = 6

    /// 「已复制」等内容区估算高度（不含 chrome 顶/底）；遗留短条契约仍保留给测试 / 旧路径。
    static let shortTipContentHeight: CGFloat = 30

    /// 「已复制」圆形微岛直径（刘海右侧 Ø32）。
    static let notchRightOrbDiameter: CGFloat = 32
    /// 微岛相对刘海右缘的空隙（略贴刘海，比稿面 8px 更靠左）。
    static let notchRightOrbGap: CGFloat = 2
    /// 方案 02 入场时长（流光→坍缩→板夹→绿勾），约 0.9s。
    static let notchRightOrbEntranceNanoseconds: UInt64 = 900_000_000
    /// 入场结束后定格再消失的时长。
    static let notchRightOrbLingerNanoseconds: UInt64 = 500_000_000
    /// 「已复制」圆岛自动收起总时长 = 入场 + 定格。
    static var notchRightOrbAutoDismissNanoseconds: UInt64 {
        notchRightOrbEntranceNanoseconds + notchRightOrbLingerNanoseconds
    }

    /// 翼 tip 单侧翼宽（与 `prepareMeetingWingNoticeLayout` 一致）。
    static let preparedWingWidth: CGFloat = 98

    /// 短 tip 上岛前强制面板尺寸（遗留；「已复制」已改圆岛）。
    static func preparedShortTipPanelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let height = shortTipTopInset(notchHeight: notchHeight)
            + shortTipContentHeight
            + shortTipBottom
        let width = max(notchWidth + 96, 260)
        return CGSize(width: width, height: height)
    }

    /// 「已复制」圆岛上岛前强制尺寸（Ø32）；须先于换皮写入。
    static func preparedNotchRightOrbPanelSize() -> CGSize {
        CGSize(width: notchRightOrbDiameter, height: notchRightOrbDiameter)
    }

    /// 相对刘海中心的水平偏移：把圆岛中心放到「刘海右缘 + gap + 半径」。
    static func notchRightOrbCenterOffsetX(notchWidth: CGFloat) -> CGFloat {
        notchWidth / 2 + notchRightOrbGap + notchRightOrbDiameter / 2
    }

    static func isNotchRightOrbPanelSize(_ size: CGSize, slop: CGFloat = 1) -> Bool {
        abs(size.width - notchRightOrbDiameter) <= slop
            && abs(size.height - notchRightOrbDiameter) <= slop
    }

    /// 翼 tip 上岛前强制面板尺寸。
    static func preparedWingTipPanelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let notchW = max(notchWidth, 110)
        let height = compactTipTopInset
            + max(notchHeight, 32)
            + compactTipBottom
        let width = preparedWingWidth * 2 + notchW + horizontalInsetTotal
        return CGSize(width: width, height: height)
    }

    /// 壳层表面类型：决定顶/底/左右 inset；`IslandBody` 与测试共用。
    /// 外形裁切另见 `IslandOutlineStyle`（提示胶囊 / 常驻上直角）。
    enum Surface: String, CaseIterable {
        /// 展开内容页（控制台 / 面板类 widget）。
        case expanded
        /// 遗留左右翼 tip inset（业务已改胶囊，勿再选用）。
        case notchWingTip
        /// 刘海正下方矮胶囊（遗留短 tip）。
        case shortBelowNotchTip
        /// 刘海右侧圆形微岛（「已复制」方案 02）；内容自撑 Ø32，无外圈 inset。
        case notchRightOrb
        /// 其它瞬时通知（普通通知顶距 + 默认底距；外形仍为胶囊）。
        case notice
    }

    struct Insets: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var horizontal: CGFloat
    }

    /// 唯一边距解析入口；禁止在 View 里再抄一套 magic。
    static func insets(for surface: Surface, notchHeight: CGFloat) -> Insets {
        switch surface {
        case .notchWingTip:
            return Insets(
                top: compactTipTopInset,
                bottom: compactTipBottom,
                horizontal: contentHorizontal
            )
        case .shortBelowNotchTip:
            return Insets(
                top: shortTipTopInset(notchHeight: notchHeight),
                bottom: shortTipBottom,
                horizontal: contentHorizontal
            )
        case .notchRightOrb:
            return Insets(top: 0, bottom: 0, horizontal: 0)
        case .notice:
            return Insets(
                top: noticeTopInset(notchHeight: notchHeight),
                bottom: contentBottom,
                horizontal: contentHorizontal
            )
        case .expanded:
            return Insets(
                top: expandedTopInset(notchHeight: notchHeight),
                bottom: contentBottom,
                horizontal: contentHorizontal
            )
        }
    }
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
    /// 「已复制」圆岛 Ø32 不得抬到刘海宽高，否则贴右锚点错位。
    static func clamp(
        _ size: CGSize,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        maxWidth: CGFloat
    ) -> CGSize {
        if IslandChrome.isNotchRightOrbPanelSize(size) {
            let d = IslandChrome.notchRightOrbDiameter
            return CGSize(
                width: NotchGeometry.pixelAlign(d),
                height: NotchGeometry.pixelAlign(d)
            )
        }
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
