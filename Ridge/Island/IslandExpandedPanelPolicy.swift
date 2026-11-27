import CoreGraphics
import Foundation

/// 展开态面板尺寸与悬停保展开的**调用入口**。
///
/// 固定契约实现在 `LockedInvariants`（未经用户授权禁止改）。本类型只转发 + 保留仍依赖壳层几何的辅助（翼 tip 等）。
///
/// 改 `IslandController` 悬停 / `IslandViewModel.panelSize` / Preference 上报前必读
/// `.cursor/rules/island-hover-retention.mdc` 与 `.cursor/rules/locked-invariants.mdc`，并跑 `RidgeTests`。
enum IslandExpandedPanelPolicy {
    static let accidentalShrinkThreshold = LockedInvariants.HoverRetention.accidentalShrinkThreshold
    static let contentScrollHoldGrace = LockedInvariants.HoverRetention.contentScrollHoldGrace
    static let fileDragApproachHorizontalOutset = LockedInvariants.HoverRetention.fileDragApproachHorizontalOutset
    static let fileDragApproachMinHeightInNotches = LockedInvariants.HoverRetention.fileDragApproachMinHeightInNotches
    static let postFileDragHoverSuppress = LockedInvariants.HoverRetention.postFileDragHoverSuppress
    static let postDownloadOpenHoverSuppress = LockedInvariants.Download.postOpenHoverSuppress
    static let collapsedInteractivePadX = LockedInvariants.HoverRetention.collapsedInteractivePadX
    static let collapsedInteractivePadY = LockedInvariants.HoverRetention.collapsedInteractivePadY

    static func shouldApplyMeasuredSize(
        current: CGSize,
        measured: CGSize,
        isExpanded: Bool,
        allowShrink: Bool,
        shrinkThreshold: CGFloat = accidentalShrinkThreshold
    ) -> Bool {
        LockedInvariants.HoverRetention.shouldApplyMeasuredSize(
            current: current,
            measured: measured,
            isExpanded: isExpanded,
            allowShrink: allowShrink,
            shrinkThreshold: shrinkThreshold
        )
    }

    static func isWingToShortTipResize(
        current: CGSize,
        measured: CGSize,
        shrinkH: CGFloat,
        shrinkThreshold: CGFloat = accidentalShrinkThreshold
    ) -> Bool {
        LockedInvariants.HoverRetention.isWingToShortTipResize(
            current: current,
            measured: measured,
            shrinkH: shrinkH,
            shrinkThreshold: shrinkThreshold
        )
    }

    static func retentionFrame(
        notchFrame: CGRect,
        panelFrame: CGRect,
        expanded: Bool,
        notchPad: CGFloat = LockedInvariants.HoverRetention.hoverExpandNotchPad,
        panelPad: CGFloat = LockedInvariants.HoverRetention.retentionPanelPad,
        panelBottomExtra: CGFloat = LockedInvariants.HoverRetention.retentionPanelBottomExtra
    ) -> CGRect {
        LockedInvariants.HoverRetention.retentionFrame(
            notchFrame: notchFrame,
            panelFrame: panelFrame,
            expanded: expanded,
            notchPad: notchPad,
            panelPad: panelPad,
            panelBottomExtra: panelBottomExtra
        )
    }

    static func hoverExpandFrame(
        notchFrame: CGRect,
        notchPad: CGFloat = LockedInvariants.HoverRetention.hoverExpandNotchPad
    ) -> CGRect {
        LockedInvariants.HoverRetention.hoverExpandFrame(notchFrame: notchFrame, notchPad: notchPad)
    }

    static func isFileDragApproachEnabled(shelfEnabled: Bool, isFileDrag: Bool) -> Bool {
        LockedInvariants.HoverRetention.isFileDragApproachEnabled(
            shelfEnabled: shelfEnabled,
            isFileDrag: isFileDrag
        )
    }

    static func isMagneticStagingEnabled(
        shelfEnabled: Bool,
        magneticEnabled: Bool,
        isFileDrag: Bool
    ) -> Bool {
        LockedInvariants.HoverRetention.isMagneticStagingEnabled(
            shelfEnabled: shelfEnabled,
            magneticEnabled: magneticEnabled,
            isFileDrag: isFileDrag
        )
    }

    static func fileDragApproachFrame(
        notchFrame: CGRect,
        horizontalOutset: CGFloat = fileDragApproachHorizontalOutset,
        minHeightInNotches: CGFloat = fileDragApproachMinHeightInNotches
    ) -> CGRect {
        LockedInvariants.HoverRetention.fileDragApproachFrame(
            notchFrame: notchFrame,
            horizontalOutset: horizontalOutset,
            minHeightInNotches: minHeightInNotches
        )
    }

    static func fileDragApproachBottomOutset(notchHeight: CGFloat) -> CGFloat {
        let h = max(notchHeight, 1)
        return max(0, h * fileDragApproachMinHeightInNotches - h)
    }

    static func shouldBlockFocusCompletedSticky(downloadCompactActive: Bool) -> Bool {
        downloadCompactActive
    }

    static func shouldExpandCollapsedForPointer(
        mouse: CGPoint,
        notchFrame: CGRect,
        isFileDrag: Bool,
        fileDragApproachContainsMouse: Bool,
        hoverExpandSuppressed: Bool = false
    ) -> Bool {
        LockedInvariants.HoverRetention.shouldExpandCollapsedForPointer(
            mouse: mouse,
            notchFrame: notchFrame,
            isFileDrag: isFileDrag,
            fileDragApproachContainsMouse: fileDragApproachContainsMouse,
            hoverExpandSuppressed: hoverExpandSuppressed
        )
    }

    static func collapsedInteractiveFrame(
        panelFrame: CGRect,
        notchFrame: CGRect
    ) -> CGRect {
        LockedInvariants.HoverRetention.collapsedInteractiveFrame(
            panelFrame: panelFrame,
            notchFrame: notchFrame
        )
    }

    static func shouldExpandCollapsedForMediaCompact(
        notchHover: Bool,
        pointerOverCompactPanel: Bool,
        mediaCompactVisible: Bool,
        hoverExpandSuppressed: Bool,
        pointerOverFocusTrailingWing: Bool = false
    ) -> Bool {
        // 右翼禁开媒体：`LockedInvariants.Media.shouldOpenMediaOnTrailingFocusWing` == false
        if pointerOverFocusTrailingWing,
           !LockedInvariants.Media.shouldOpenMediaOnTrailingFocusWing()
        {
            return false
        }
        return LockedInvariants.HoverRetention.shouldExpandCollapsedForMediaCompact(
            notchHover: notchHover,
            pointerOverCompactPanel: pointerOverCompactPanel,
            mediaCompactVisible: mediaCompactVisible,
            hoverExpandSuppressed: hoverExpandSuppressed,
            pointerOverFocusTrailingWing: pointerOverFocusTrailingWing
        )
    }

    static func isFocusTrailingDualStandby(
        mediaVisible: Bool,
        downloadActive: Bool,
        focusStandby: Bool,
        hasNoticePayload: Bool
    ) -> Bool {
        guard focusStandby, !hasNoticePayload else { return false }
        if mediaVisible {
            return !downloadActive
        }
        return downloadActive
    }

    static func isPointerOverFocusTrailingWing(
        mouse: CGPoint,
        notchFrame: CGRect,
        panelFrame: CGRect,
        focusTrailingDualVisible: Bool
    ) -> Bool {
        guard focusTrailingDualVisible else { return false }
        let hit = collapsedInteractiveFrame(panelFrame: panelFrame, notchFrame: notchFrame)
        guard hit.contains(mouse) else { return false }
        let trailingStart = notchFrame.maxX - IslandChrome.dualFlushNotchUnderlap
        return mouse.x >= trailingStart
    }

    static func isPointerOverMediaFocusTrailingWing(
        mouse: CGPoint,
        notchFrame: CGRect,
        mediaFocusDualVisible: Bool
    ) -> Bool {
        guard mediaFocusDualVisible else { return false }
        return mouse.x > notchFrame.maxX
    }

    static func shouldForceCollapseAfterShelfFileDragMouseUp(
        hadShelfFileDragExpand: Bool,
        dropCompletedRecently: Bool,
        isExpanded: Bool,
        pointerInExpandedRetention: Bool
    ) -> Bool {
        LockedInvariants.HoverRetention.shouldForceCollapseAfterShelfFileDragMouseUp(
            hadShelfFileDragExpand: hadShelfFileDragExpand,
            dropCompletedRecently: dropCompletedRecently,
            isExpanded: isExpanded,
            pointerInExpandedRetention: pointerInExpandedRetention
        )
    }

    static func isCollapsedSizedWhileExpanded(
        panel: CGSize,
        notch: CGSize,
        isExpanded: Bool,
        slop: CGFloat = 8
    ) -> Bool {
        LockedInvariants.HoverRetention.isCollapsedSizedWhileExpanded(
            panel: panel,
            notch: notch,
            isExpanded: isExpanded,
            slop: slop
        )
    }

    static func expandedRetentionFloor(notch: CGSize) -> CGSize {
        LockedInvariants.HoverRetention.expandedRetentionFloor(notch: notch)
    }

    static func resolvedRetentionPanelSize(
        panel: CGSize,
        stable: CGSize,
        notch: CGSize,
        isExpanded: Bool
    ) -> CGSize {
        LockedInvariants.HoverRetention.resolvedRetentionPanelSize(
            panel: panel,
            stable: stable,
            notch: notch,
            isExpanded: isExpanded
        )
    }

    static func retentionContainsMidLowerPoint(
        notchFrame: CGRect,
        panelFrame: CGRect,
        expanded: Bool
    ) -> Bool {
        LockedInvariants.HoverRetention.retentionContainsMidLowerPoint(
            notchFrame: notchFrame,
            panelFrame: panelFrame,
            expanded: expanded
        )
    }

    static func isTransientShortPanel(
        _ panel: CGSize,
        notch: CGSize,
        maxHeightAboveNotch: CGFloat = 48,
        maxWidthAboveNotch: CGFloat = 140
    ) -> Bool {
        LockedInvariants.HoverRetention.isTransientShortPanel(
            panel,
            notch: notch,
            maxHeightAboveNotch: maxHeightAboveNotch,
            maxWidthAboveNotch: maxWidthAboveNotch
        )
    }

    static func shouldPreferStableRetention(
        panel: CGSize,
        stable: CGSize,
        notch: CGSize,
        isExpanded: Bool,
        heightSlop: CGFloat = 40,
        widthSlop: CGFloat = 80
    ) -> Bool {
        LockedInvariants.HoverRetention.shouldPreferStableRetention(
            panel: panel,
            stable: stable,
            notch: notch,
            isExpanded: isExpanded,
            heightSlop: heightSlop,
            widthSlop: widthSlop
        )
    }

    static func shouldHoldExpandForRecentScroll(
        lastScrollAt: Date?,
        now: Date = Date(),
        grace: TimeInterval = contentScrollHoldGrace
    ) -> Bool {
        LockedInvariants.HoverRetention.shouldHoldExpandForRecentScroll(
            lastScrollAt: lastScrollAt,
            now: now,
            grace: grace
        )
    }

    static func wingTipInteractivePanelSize(
        current: CGSize,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        usesNotchWingChrome: Bool,
        wingWidth: CGFloat = IslandChrome.preparedWingWidth,
        focusCompletedFlush: Bool = false
    ) -> CGSize {
        guard usesNotchWingChrome else { return current }
        let prepared: CGSize = {
            if focusCompletedFlush {
                return IslandChrome.preparedFocusCompletedPanelSize(
                    notchWidth: notchWidth + FocusTimerContentSize.completedCenterExtra,
                    notchHeight: notchHeight
                )
            }
            return IslandChrome.preparedWingTipPanelSize(
                notchWidth: notchWidth,
                notchHeight: notchHeight,
                wingWidth: wingWidth
            )
        }()
        return CGSize(
            width: max(current.width, prepared.width),
            height: max(current.height, prepared.height)
        )
    }

    static func shouldForceStickyNoticeExpand(
        isExpanded: Bool,
        keepsExpandedWithoutHover: Bool,
        settingsSessionBlocksIslandTips: Bool,
        pointerOverSettings: Bool,
        expandsDuringSettingsSession: Bool = false
    ) -> Bool {
        LockedInvariants.Notice.shouldForceStickyNoticeExpand(
            isExpanded: isExpanded,
            keepsExpandedWithoutHover: keepsExpandedWithoutHover,
            settingsSessionBlocksIslandTips: settingsSessionBlocksIslandTips,
            pointerOverSettings: pointerOverSettings,
            expandsDuringSettingsSession: expandsDuringSettingsSession
        )
    }

    static func settingsBlocksProgrammaticNoticeExpand(
        sessionActive: Bool,
        livePreview: Bool,
        designSticky: Bool
    ) -> Bool {
        LockedInvariants.Notice.settingsBlocksProgrammaticNoticeExpand(
            sessionActive: sessionActive,
            livePreview: livePreview,
            designSticky: designSticky
        )
    }
}
