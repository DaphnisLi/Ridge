import CoreGraphics
import Foundation

/// 展开态面板尺寸与悬停保展开的**唯一策略入口**。
///
/// # 不变量（违反即回归「大岛拖一下就收」）
/// 1. 展开态保展开热区必须跟**当前可见大面板**走，禁止退回刘海小框。
/// 2. 展开态内容 Preference 可以变大，但**禁止**在非翻页窗口内大幅缩小（拖动/滚动会误报矮框）。
/// 3. 左键在岛上按下后的拖动，松开前不得因热区抖动收岛。
/// 4. 控制台列表纵滑（无左键按下）后短时内不得 `collapse(hoverEnd)`——滚到一半指针微移会误判离开。
///
/// 改 `IslandController` 悬停 / `IslandViewModel.panelSize` / Preference 上报前必读
/// `.cursor/rules/island-hover-retention.mdc`，并跑 `RidgeTests`。
enum IslandExpandedPanelPolicy {
    /// 相对当前尺寸，单边缩小超过此值视为「误缩」（常见是缩回刘海）。
    static let accidentalShrinkThreshold: CGFloat = 28
    /// 内容区纵滑结束后仍保展开的宽限（秒）。
    static let contentScrollHoldGrace: TimeInterval = 0.55

    /// 展开态是否应采纳本次内容测量。
    /// - Parameters:
    ///   - allowShrink: 翻页 / 刚展开 / 番茄态切换等布局重置窗口内为 true。
    static func shouldApplyMeasuredSize(
        current: CGSize,
        measured: CGSize,
        isExpanded: Bool,
        allowShrink: Bool,
        shrinkThreshold: CGFloat = accidentalShrinkThreshold
    ) -> Bool {
        guard abs(measured.width - current.width) > 0.5
            || abs(measured.height - current.height) > 0.5
        else {
            return false
        }
        guard isExpanded, !allowShrink else { return true }
        let shrinkW = current.width - measured.width
        let shrinkH = current.height - measured.height
        if shrinkW > shrinkThreshold || shrinkH > shrinkThreshold {
            // shelf-copied-notice-miss：宽翼引导→「已复制」圆岛/短条必缩宽。
            // 若因缩宽整单拒绝，面板卡在翼尺寸，提示看不见。
            if isWingToShortTipResize(current: current, measured: measured, shrinkH: shrinkH, shrinkThreshold: shrinkThreshold) {
                return true
            }
            return false
        }
        return true
    }

    /// 宽翼 tip → 瞬时 tip（圆岛 Ø32 / 遗留短条）：允许明显缩宽。
    static func isWingToShortTipResize(
        current: CGSize,
        measured: CGSize,
        shrinkH: CGFloat,
        shrinkThreshold: CGFloat = accidentalShrinkThreshold
    ) -> Bool {
        // 高度仍在大幅变矮（缩回异常框）→ 不走此放行。
        guard shrinkH <= shrinkThreshold else { return false }
        // 「已复制」圆岛固定 Ø32，相对翼 tip 可略矮。
        if IslandChrome.isNotchRightOrbPanelSize(measured) { return true }
        // 新尺寸不比当前更矮（允许略浮点误差）→ 视为 tip 替换而非误缩。
        return measured.height + 1 >= current.height
    }

    /// 展开态保展开矩形：面板框外扩 ∪ 刘海。
    /// 收起态：当前可见小岛（`panelFrame`）∪ 刘海——播放/番茄小岛宽于刘海时，翼上也须能悬停展开，禁止只用 notch。
    /// 下边多留一点：纵滑 / 滚到面板下沿时不易误判离开。
    static func retentionFrame(
        notchFrame: CGRect,
        panelFrame: CGRect,
        expanded: Bool,
        notchPad: CGFloat = 4,
        panelPad: CGFloat = 16,
        panelBottomExtra: CGFloat = 20
    ) -> CGRect {
        let notchHit = notchFrame.insetBy(dx: -notchPad, dy: -2)
        if !expanded {
            let compactHit = panelFrame.insetBy(dx: -2, dy: -2)
            return compactHit.union(notchHit)
        }
        let padded = panelFrame.insetBy(dx: -panelPad, dy: -panelPad)
        let withBottom = CGRect(
            x: padded.origin.x,
            y: padded.origin.y - panelBottomExtra,
            width: padded.width,
            height: padded.height + panelBottomExtra
        )
        return withBottom.union(notchHit)
    }

    /// 展开且面板已接近刘海尺寸时视为异常（热区会退化成「小岛」）。
    static func isCollapsedSizedWhileExpanded(
        panel: CGSize,
        notch: CGSize,
        isExpanded: Bool,
        slop: CGFloat = 8
    ) -> Bool {
        guard isExpanded else { return false }
        return panel.width <= notch.width + slop && panel.height <= notch.height + slop
    }

    /// 「已复制」/ AI 额度等瞬时短条：可见面板可以变矮，但绝不能当成稳定大面板写入 `lastStable`。
    static func isTransientShortPanel(
        _ panel: CGSize,
        notch: CGSize,
        maxHeightAboveNotch: CGFloat = 48,
        maxWidthAboveNotch: CGFloat = 140
    ) -> Bool {
        panel.height <= notch.height + maxHeightAboveNotch
            || panel.width <= notch.width + maxWidthAboveNotch
    }

    /// 当前面板相对已记录大面板明显缩水时，保展开仍用大面板（短通知盖住大岛）。
    static func shouldPreferStableRetention(
        panel: CGSize,
        stable: CGSize,
        notch: CGSize,
        isExpanded: Bool,
        heightSlop: CGFloat = 40,
        widthSlop: CGFloat = 80
    ) -> Bool {
        guard isExpanded else { return false }
        guard stable.width > notch.width + 8, stable.height > notch.height + 8 else {
            return false
        }
        if isCollapsedSizedWhileExpanded(panel: panel, notch: notch, isExpanded: true) {
            return true
        }
        if isTransientShortPanel(panel, notch: notch) {
            return true
        }
        return panel.height + heightSlop < stable.height
            || panel.width + widthSlop < stable.width
    }

    /// 列表纵滑后宽限内应钉住展开（触控板/鼠标滚轮无左键，不能靠 dragHold）。
    static func shouldHoldExpandForRecentScroll(
        lastScrollAt: Date?,
        now: Date = Date(),
        grace: TimeInterval = contentScrollHoldGrace
    ) -> Bool {
        guard let lastScrollAt else { return false }
        return now.timeIntervalSince(lastScrollAt) < grace
    }
}
