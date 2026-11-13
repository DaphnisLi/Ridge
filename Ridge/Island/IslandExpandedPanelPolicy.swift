import CoreGraphics
import Foundation

/// 展开态面板尺寸与悬停保展开的**唯一策略入口**。
///
/// # 不变量（违反即回归「大岛拖一下就收」/「移入刘海外就展开」）
/// 1. 展开态保展开热区必须跟**当前可见大面板**走，禁止退回刘海小框。
/// 2. 收起态悬停展开仅刘海；控制台外扩接近区只在拖文件时用。
/// 3. 展开态内容 Preference 可以变大，但**禁止**在非翻页窗口内大幅缩小（拖动/滚动会误报矮框）。
/// 4. 左键在岛上按下后的拖动，松开前不得因热区抖动收岛。
/// 5. 控制台列表纵滑（无左键按下）后短时内不得 `collapse(hoverEnd)`——滚到一半指针微移会误判离开。
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

    /// 展开态保展开矩形：面板框外扩 ∪ 刘海（下边多留，纵滑不易误收）。
    /// 收起态悬停「识别 / 展开」：仅刘海。大接近区只给拖文件（见 `fileDragApproachFrame`），
    /// 禁止把控制台外扩热区或宽于刘海的播放/番茄翼当成普通移入展开区。
    static func retentionFrame(
        notchFrame: CGRect,
        panelFrame: CGRect,
        expanded: Bool,
        notchPad: CGFloat = 4,
        panelPad: CGFloat = 16,
        panelBottomExtra: CGFloat = 20
    ) -> CGRect {
        let notchHit = hoverExpandFrame(notchFrame: notchFrame, notchPad: notchPad)
        if !expanded {
            _ = panelFrame // 收起态悬停展开不跟可见小岛走；可点区仍由 interactive 含翼。
            return notchHit
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

    /// 非拖文件时收起态悬停展开 / 识别热区：刘海（略外扩防贴边抖）。
    static func hoverExpandFrame(
        notchFrame: CGRect,
        notchPad: CGFloat = 4
    ) -> CGRect {
        notchFrame.insetBy(dx: -notchPad, dy: -2)
    }

    /// 拖文件接近区相对刘海左右外扩（pt）。宽度跟刘海，默认 0。
    static let fileDragApproachHorizontalOutset: CGFloat = 0
    /// 接近区总高度至少为刘海高的倍数（含刘海本身）。
    static let fileDragApproachMinHeightInNotches: CGFloat = 3

    /// 拖文件接近区是否启用：只看货架开 + 正在拖文件，**与磁吸开关无关**。
    static func isFileDragApproachEnabled(shelfEnabled: Bool, isFileDrag: Bool) -> Bool {
        shelfEnabled && isFileDrag
    }

    /// 双舱 / 隔空传送：须磁吸开 + 货架开 + 拖文件。
    static func isMagneticStagingEnabled(
        shelfEnabled: Bool,
        magneticEnabled: Bool,
        isFileDrag: Bool
    ) -> Bool {
        shelfEnabled && magneticEnabled && isFileDrag
    }

    /// 拖文件接近区（仅 `fileDrag`）：宽≈刘海，高≥3 倍刘海（向下延伸，躲开调度中心）。
    /// 几何与磁吸开关无关；禁止用控制台 660×300 当地基。
    static func fileDragApproachFrame(
        notchFrame: CGRect,
        horizontalOutset: CGFloat = fileDragApproachHorizontalOutset,
        minHeightInNotches: CGFloat = fileDragApproachMinHeightInNotches
    ) -> CGRect {
        let notchH = max(notchFrame.height, 1)
        let targetH = max(notchH * minHeightInNotches, notchH)
        let bottomOutset = max(0, targetH - notchH)
        var zone = notchFrame.insetBy(dx: -horizontalOutset, dy: 0)
        zone.origin.y -= bottomOutset
        zone.size.height += bottomOutset
        return zone
    }

    /// 接近区相对刘海底边向下的外扩量（便于测试 / 日志）。
    static func fileDragApproachBottomOutset(notchHeight: CGFloat) -> CGFloat {
        let h = max(notchHeight, 1)
        return max(0, h * fileDragApproachMinHeightInNotches - h)
    }

    /// 拖文件会话结束后短暂禁止「普通悬停再展开」，避免未入舱松手后岛立刻又弹开。
    static let postFileDragHoverSuppress: TimeInterval = 0.55

    /// 收起态是否应因指针位置展开。
    /// - 拖文件：接近区或刘海均可。
    /// - 普通移入：仅刘海；接近区 / 播放翼外侧不算。
    /// - `hoverExpandSuppressed`：未入舱松手后的冷却，挡住回头再开。
    static func shouldExpandCollapsedForPointer(
        mouse: CGPoint,
        notchFrame: CGRect,
        isFileDrag: Bool,
        fileDragApproachContainsMouse: Bool,
        hoverExpandSuppressed: Bool = false
    ) -> Bool {
        if isFileDrag {
            if fileDragApproachContainsMouse { return true }
            return hoverExpandFrame(notchFrame: notchFrame).contains(mouse)
        }
        if hoverExpandSuppressed { return false }
        return hoverExpandFrame(notchFrame: notchFrame).contains(mouse)
    }

    /// 因货架拖文件而展开后，鼠标松开且未刚完成投放 → 应强制收起（防未入舱却留着大岛 / 回头再开）。
    static func shouldForceCollapseAfterShelfFileDragMouseUp(
        hadShelfFileDragExpand: Bool,
        dropCompletedRecently: Bool,
        isExpanded: Bool
    ) -> Bool {
        hadShelfFileDragExpand && !dropCompletedRecently && isExpanded
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

    /// Preference 未到 / 误报矮框时，展开态保展开不得矮于此下限（否则下半截一移就收）。
    /// 宽约媒体/番茄下限，高须明显超过刘海，覆盖「移动一半」的指针位置。
    static func expandedRetentionFloor(notch: CGSize) -> CGSize {
        CGSize(
            width: max(notch.width + 120, 320),
            height: max(notch.height + 120, 160)
        )
    }

    /// 解析展开态保展开用的面板尺寸（稳定大面板优先，其次当前面板，矮框则抬到下限）。
    static func resolvedRetentionPanelSize(
        panel: CGSize,
        stable: CGSize,
        notch: CGSize,
        isExpanded: Bool
    ) -> CGSize {
        if shouldPreferStableRetention(
            panel: panel,
            stable: stable,
            notch: notch,
            isExpanded: isExpanded
        ) {
            return stable
        }
        guard isExpanded else { return panel }
        if isCollapsedSizedWhileExpanded(panel: panel, notch: notch, isExpanded: true) {
            let floor = expandedRetentionFloor(notch: notch)
            return CGSize(
                width: max(panel.width, floor.width),
                height: max(panel.height, floor.height)
            )
        }
        // 已高于刘海但仍明显矮于稳定大面板时，上面 shouldPrefer 已处理；这里直接用当前面板。
        return panel
    }

    /// 大面板竖直中下点是否仍在保展开区内（「移动一半就收」回归锚点）。
    static func retentionContainsMidLowerPoint(
        notchFrame: CGRect,
        panelFrame: CGRect,
        expanded: Bool
    ) -> Bool {
        let frame = retentionFrame(
            notchFrame: notchFrame,
            panelFrame: panelFrame,
            expanded: expanded
        )
        let midLower = CGPoint(x: panelFrame.midX, y: panelFrame.minY + panelFrame.height * 0.25)
        return frame.contains(midLower)
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
