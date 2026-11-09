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
        // 仅刘海时，下半截不应命中。
        let notchOnly = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: false
        )
        XCTAssertFalse(notchOnly.contains(lowerPoint))
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
