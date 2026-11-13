import XCTest
@testable import Ridge

final class IslandExpandedPanelPolicyTests: XCTestCase {
    func testRejectsAccidentalShrinkWhileExpanded() {
        let current = CGSize(width: 660, height: 300)
        let notchSized = CGSize(width: 180, height: 32)
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: current,
                measured: notchSized,
                isExpanded: true,
                allowShrink: false
            )
        )
    }

    /// 展开态面板仍为刘海尺寸时，resolvedRetention 须抬到下限且中下点命中。
    func testExpandedRetentionFloorKeepsMidLowerPoint() {
        let notch = CGSize(width: 180, height: 32)
        let compact = notch
        let resolved = IslandExpandedPanelPolicy.resolvedRetentionPanelSize(
            panel: compact,
            stable: .zero,
            notch: notch,
            isExpanded: true
        )
        let floor = IslandExpandedPanelPolicy.expandedRetentionFloor(notch: notch)
        XCTAssertEqual(resolved.height, floor.height, accuracy: 0.5)
        XCTAssertEqual(resolved.width, floor.width, accuracy: 0.5)

        let notchFrame = CGRect(x: 400, y: 968, width: 180, height: 32)
        let panelFrame = CGRect(
            x: 400 + 90 - resolved.width / 2,
            y: 1000 - resolved.height,
            width: resolved.width,
            height: resolved.height
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.retentionContainsMidLowerPoint(
                notchFrame: notchFrame,
                panelFrame: panelFrame,
                expanded: true
            )
        )
    }

    func testAllowsShrinkDuringLayoutResetWindow() {
        let current = CGSize(width: 660, height: 300)
        let next = CGSize(width: 388, height: 80)
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: current,
                measured: next,
                isExpanded: true,
                allowShrink: true
            )
        )
    }

    /// shelf-copied-notice-miss：翼 tip→「已复制」圆岛即使不在 allowShrink 窗口也须放行缩宽。
    func testAllowsWingTipToShortCopiedResizeWithoutAllowShrink() {
        let notchW: CGFloat = 160
        let notchH: CGFloat = 32
        let wing = IslandChrome.preparedWingTipPanelSize(notchWidth: notchW, notchHeight: notchH)
        let orb = IslandChrome.preparedNotchRightOrbPanelSize()
        XCTAssertGreaterThan(wing.width, orb.width, "翼 tip 应明显宽于圆岛")
        XCTAssertTrue(IslandChrome.isNotchRightOrbPanelSize(orb))
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: wing,
                measured: orb,
                isExpanded: true,
                allowShrink: false
            ),
            "宽翼→已复制圆岛不得因缩宽被误缩守卫拒绝"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isWingToShortTipResize(
                current: wing,
                measured: orb,
                shrinkH: wing.height - orb.height
            )
        )
    }

    func testStillRejectsLargePanelShrinkToNotchWithoutAllowShrink() {
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: CGSize(width: 660, height: 300),
                measured: CGSize(width: 180, height: 32),
                isExpanded: true,
                allowShrink: false
            )
        )
    }

    func testAllowsGrowthWhileExpanded() {
        let current = CGSize(width: 388, height: 80)
        let taller = CGSize(width: 388, height: 278)
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: current,
                measured: taller,
                isExpanded: true,
                allowShrink: false
            )
        )
    }

    func testCollapsedStateAlwaysAcceptsResize() {
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: CGSize(width: 180, height: 32),
                measured: CGSize(width: 200, height: 36),
                isExpanded: false,
                allowShrink: false
            )
        )
    }

    func testRetentionUsesPanelNotOnlyNotchWhenExpanded() {
        let notch = CGRect(x: 400, y: 900, width: 180, height: 32)
        let panel = CGRect(x: 200, y: 700, width: 660, height: 300)
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: true
        )
        // 大面板下半截必须在保展开区内。
        let lowerPoint = CGPoint(x: panel.midX, y: panel.minY + 20)
        XCTAssertTrue(frame.contains(lowerPoint))
        // 下边额外外扩：贴底外侧一点仍应保展开。
        let belowPanel = CGPoint(x: panel.midX, y: panel.minY - 10)
        XCTAssertTrue(frame.contains(belowPanel))
        // 收起且小岛≈刘海时，大面板下半截不在保展开区。
        let collapsedNotchSized = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: notch,
            expanded: false
        )
        XCTAssertFalse(collapsedNotchSized.contains(lowerPoint))
    }

    /// 收起态悬停展开仅刘海；宽于刘海的播放翼不算（大接近区只给拖文件）。
    func testCollapsedHoverExpandUsesNotchOnlyNotWings() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let mediaCompact = CGRect(x: 311, y: 968, width: 380, height: 32)
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: mediaCompact,
            expanded: false
        )
        let leftWing = CGPoint(x: mediaCompact.minX + 16, y: mediaCompact.midY)
        let rightWing = CGPoint(x: mediaCompact.maxX - 16, y: mediaCompact.midY)
        let inNotch = CGPoint(x: notch.midX, y: notch.midY)
        XCTAssertFalse(frame.contains(leftWing), "左翼不得悬停展开")
        XCTAssertFalse(frame.contains(rightWing), "右翼不得悬停展开")
        XCTAssertTrue(frame.contains(inNotch), "刘海内须可悬停展开")
        XCTAssertFalse(notch.contains(leftWing), "左翼本就不在刘海内")
    }

    func testDetectsCollapsedSizedWhileExpanded() {
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: CGSize(width: 180, height: 32),
                notch: CGSize(width: 180, height: 32),
                isExpanded: true
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: CGSize(width: 660, height: 300),
                notch: CGSize(width: 180, height: 32),
                isExpanded: true
            )
        )
    }

    func testTransientShortPanelDoesNotCountAsStableContent() {
        let notch = CGSize(width: 179, height: 32)
        // 「已复制」短条约 275×68：相对刘海仍偏矮，属瞬时短条。
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isTransientShortPanel(
                CGSize(width: 275, height: 68),
                notch: notch
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isTransientShortPanel(
                CGSize(width: 348, height: 175),
                notch: notch
            )
        )
    }

    func testPreferStableRetentionWhenShortTipCoversLargePanel() {
        let notch = CGSize(width: 179, height: 32)
        let stable = CGSize(width: 660, height: 300)
        let tip = CGSize(width: 275, height: 68)
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldPreferStableRetention(
                panel: tip,
                stable: stable,
                notch: notch,
                isExpanded: true
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldPreferStableRetention(
                panel: stable,
                stable: stable,
                notch: notch,
                isExpanded: true
            )
        )
    }
}
