import Combine
import CoreGraphics
import Foundation

enum IslandAppearance: Equatable {
    case compact
    case expanded
}

@MainActor
final class IslandViewModel: ObservableObject {
    @Published var appearance: IslandAppearance = .compact
    @Published var isHiddenForFullscreen = false
    @Published var isVisibleOnDisplay = true
    @Published var notchHeight: CGFloat = 32
    @Published var notchWidth: CGFloat = 160
    /// 展开宽度上限（屏宽减去边距）；与 NotchGeometry.maxExpandedWidth 一致。
    @Published var maxExpandedWidth: CGFloat = 2000
    /// 当前可见面板尺寸：收起为刘海/待命宽高；展开由内容测量 + IslandChrome 撑开。
    @Published var panelSize: CGSize = CGSize(width: 160, height: 32)
    /// 最近一次「正常大面板」尺寸；保展开热区优先用它，避免误缩成刘海后下半截一碰就收岛。
    private(set) var lastStableExpandedPanelSize: CGSize = .zero
    /// 翻页 / 刚展开时允许面板变矮变窄；其余时间禁止大幅缩小（拖动时 Preference 会误报刘海尺寸）。
    private var allowPanelShrinkUntil = Date.distantPast

    var isExpanded: Bool { appearance == .expanded }

    /// 展开态悬停热区用的面板尺寸：禁止退回接近刘海 / 瞬时短条的小框。
    /// Preference 未到时若仍停在刘海尺寸，抬到 `expandedRetentionFloor`，避免下半截一移就收。
    func retentionPanelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        let notch = CGSize(width: notchWidth, height: notchHeight)
        return IslandExpandedPanelPolicy.resolvedRetentionPanelSize(
            panel: panelSize,
            stable: lastStableExpandedPanelSize,
            notch: notch,
            isExpanded: isExpanded
        )
    }

    func toggle() {
        appearance = isExpanded ? .compact : .expanded
    }

    func expand() {
        appearance = .expanded
        allowPanelShrink(for: 0.7, reason: "expand")
    }

    func collapse() {
        appearance = .compact
    }

    /// 翻页或布局重置后短暂允许缩小到新页真实尺寸。
    func allowPanelShrink(for seconds: TimeInterval = 0.55, reason: String) {
        allowPanelShrinkUntil = Date().addingTimeInterval(seconds)
        AppLog.debug("Island", "允许面板缩小", [
            "seconds": seconds,
            "reason": reason
        ])
    }

    /// 通知替换等：绕过误缩守卫，立刻写入**可见**面板尺寸（再交给 Preference 微调）。
    /// 短条尺寸**禁止**写入 `lastStableExpandedPanelSize`，否则大岛保展开热区会退化成 tip 小框。
    func forcePanelSize(_ raw: CGSize, reason: String) {
        allowPanelShrink(for: 1.2, reason: reason)
        let next = IslandPanelSizing.clamp(
            raw,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            maxWidth: maxExpandedWidth
        )
        panelSize = next
        let notch = CGSize(width: notchWidth, height: notchHeight)
        let writeStable = isExpanded
            && !IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: next,
                notch: notch,
                isExpanded: true
            )
            && !IslandExpandedPanelPolicy.isTransientShortPanel(next, notch: notch)
        if writeStable {
            lastStableExpandedPanelSize = next
        }
        AppLog.warn("Island", "强制写入面板尺寸", [
            "reason": reason,
            "w": Int(next.width),
            "h": Int(next.height),
            "writeStable": writeStable,
            "stableW": Int(lastStableExpandedPanelSize.width),
            "stableH": Int(lastStableExpandedPanelSize.height)
        ])
    }

    /// 内容 Preference 上报后写入；变化过小则忽略，避免布局抖动。
    func applyMeasuredPanelSize(_ raw: CGSize) {
        let next = IslandPanelSizing.clamp(
            raw,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            maxWidth: maxExpandedWidth
        )
        guard abs(next.width - panelSize.width) > 0.5
            || abs(next.height - panelSize.height) > 0.5
        else { return }

        let allowShrink = Date() <= allowPanelShrinkUntil
        guard IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
            current: panelSize,
            measured: next,
            isExpanded: isExpanded,
            allowShrink: allowShrink
        ) else {
            if isExpanded, !allowShrink {
                AppLog.warn("Island", "忽略展开态面板误缩", [
                    "fromW": Int(panelSize.width),
                    "fromH": Int(panelSize.height),
                    "toW": Int(next.width),
                    "toH": Int(next.height),
                    "notchW": Int(notchWidth),
                    "notchH": Int(notchHeight)
                ])
            }
            return
        }

        panelSize = next
        let notch = CGSize(width: notchWidth, height: notchHeight)
        if IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
            panel: next,
            notch: notch,
            isExpanded: isExpanded
        ) {
            AppLog.warn("Island", "展开态面板尺寸异常接近刘海", [
                "w": Int(next.width),
                "h": Int(next.height),
                "notchW": Int(notchWidth),
                "notchH": Int(notchHeight)
            ])
        } else if isExpanded,
                  !IslandExpandedPanelPolicy.isTransientShortPanel(next, notch: notch) {
            lastStableExpandedPanelSize = next
        } else if isExpanded {
            AppLog.debug("Island", "短条尺寸不写入 lastStable", [
                "w": Int(next.width),
                "h": Int(next.height),
                "stableW": Int(lastStableExpandedPanelSize.width),
                "stableH": Int(lastStableExpandedPanelSize.height)
            ])
        }
        AppLog.debug("Island", "面板尺寸由内容更新", [
            "w": next.width,
            "h": next.height,
            "expanded": isExpanded
        ])
    }
}
