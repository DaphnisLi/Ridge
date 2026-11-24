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

    /// island-hover-retention：选时岛更宽更矮时，保展开宽须盖住当前面板（含右侧「正计时」）。
    func test_islandHoverRetention_pickingWiderThanStableUnionsWidth() {
        let notch = CGSize(width: 179, height: 32)
        // 上一页媒体/控制台：更高更窄；选时：更宽更矮（日志 panelW=447 stableW=334）。
        let stable = CGSize(width: 334, height: 142)
        let picking = CGSize(width: 447, height: 73)
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldPreferStableRetention(
                panel: picking,
                stable: stable,
                notch: notch,
                isExpanded: true
            ),
            "选时更矮时应倾向保留稳定高度"
        )
        let resolved = IslandExpandedPanelPolicy.resolvedRetentionPanelSize(
            panel: picking,
            stable: stable,
            notch: notch,
            isExpanded: true
        )
        XCTAssertGreaterThanOrEqual(
            resolved.width,
            picking.width - 0.5,
            "保展开宽不得窄于选时岛，否则右侧「正计时」出热区"
        )
        XCTAssertGreaterThanOrEqual(
            resolved.height,
            stable.height - 0.5,
            "仍须保留上一页稳定高度，避免下半截误收"
        )

        let notchFrame = CGRect(x: 400, y: 968, width: notch.width, height: notch.height)
        let screenMaxY: CGFloat = 1000
        let retentionFrame = CGRect(
            x: notchFrame.midX - resolved.width / 2,
            y: screenMaxY - resolved.height,
            width: resolved.width,
            height: resolved.height
        )
        let visiblePicking = CGRect(
            x: notchFrame.midX - picking.width / 2,
            y: screenMaxY - picking.height,
            width: picking.width,
            height: picking.height
        )
        let countUpButton = CGPoint(x: visiblePicking.maxX - 24, y: visiblePicking.midY)
        XCTAssertTrue(
            retentionFrame.contains(countUpButton),
            "选时右侧「正计时」须仍在保展开区内"
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

    /// island-hover-retention / media-compact-not-resident：收起可点框外扩，右计时翼贴边仍算在岛上。
    func test_islandHoverRetention_collapsedInteractivePadsFocusTrailingWing() {
        XCTAssertGreaterThanOrEqual(
            IslandExpandedPanelPolicy.collapsedInteractivePadX,
            28,
            "双翼右缘外扩过小会未出岛就穿透收 morph"
        )
        let notch = CGRect(x: 400, y: 900, width: 160, height: 32)
        // dualFlush：左翼 120 + 刘海 160 + 右翼 120
        let dual = CGRect(x: 280, y: 900, width: 400, height: 32)
        let hit = IslandExpandedPanelPolicy.collapsedInteractiveFrame(
            panelFrame: dual,
            notchFrame: notch
        )
        let rightEdgeInside = CGPoint(x: dual.maxX - 2, y: dual.midY)
        let rightEdgePadded = CGPoint(
            x: dual.maxX + IslandExpandedPanelPolicy.collapsedInteractivePadX - 2,
            y: dual.midY
        )
        XCTAssertTrue(hit.contains(rightEdgeInside), "右翼内缘须可点")
        XCTAssertTrue(hit.contains(rightEdgePadded), "右翼外扩须保活，避免 morph 误收")

        XCTAssertTrue(
            IslandExpandedPanelPolicy.isFocusTrailingDualStandby(
                mediaVisible: true,
                downloadActive: false,
                focusStandby: true,
                hasNoticePayload: false
            )
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isFocusTrailingDualStandby(
                mediaVisible: false,
                downloadActive: true,
                focusStandby: true,
                hasNoticePayload: false
            ),
            "左下载右计时也是右计时翼"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isFocusTrailingDualStandby(
                mediaVisible: true,
                downloadActive: true,
                focusStandby: true,
                hasNoticePayload: false
            ),
            "音乐+下载时右翼是下载，不是计时"
        )

        XCTAssertTrue(
            IslandExpandedPanelPolicy.isPointerOverFocusTrailingWing(
                mouse: rightEdgeInside,
                notchFrame: notch,
                panelFrame: dual,
                focusTrailingDualVisible: true
            )
        )
        // 右翼 underlap 伸进刘海：贴右缘内侧也须认成右计时翼，否则点暂停会误开媒体。
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isPointerOverFocusTrailingWing(
                mouse: CGPoint(x: notch.maxX - 6, y: dual.midY),
                notchFrame: notch,
                panelFrame: dual,
                focusTrailingDualVisible: true
            ),
            "刘海右缘 underlap 内须算右计时翼"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isPointerOverFocusTrailingWing(
                mouse: CGPoint(x: notch.midX, y: notch.midY),
                notchFrame: notch,
                panelFrame: dual,
                focusTrailingDualVisible: true
            ),
            "刘海中线不算右计时翼"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isPointerOverFocusTrailingWing(
                mouse: CGPoint(x: dual.maxX + 80, y: dual.midY),
                notchFrame: notch,
                panelFrame: dual,
                focusTrailingDualVisible: true
            ),
            "远出外扩区外不算在岛上"
        )
    }

    /// media-compact-not-resident：右计时翼命中时不得开媒体。
    func test_mediaCompactNotResident_focusTrailingWingBlocksMediaExpand() {
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: false,
                pointerOverCompactPanel: true,
                mediaCompactVisible: true,
                hoverExpandSuppressed: false,
                pointerOverFocusTrailingWing: true
            )
        )
    }

    /// media-compact-not-resident / island-focus-steal：正计时岛宽只在跨小时档变，禁止每秒缩扩抖 hover/点空。
    func test_mediaCompactNotResident_countUpStandbyWidthStableUntilHours() {
        let underHourA = NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 45)
        let underHourB = NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 3599)
        XCTAssertEqual(underHourA, underHourB, "不足 1h 岛宽须恒定，勿每秒变")
        XCTAssertFalse(FocusTimerFormatting.countUpShowsHours(45))
        XCTAssertFalse(FocusTimerFormatting.countUpShowsHours(3599))
        XCTAssertTrue(FocusTimerFormatting.countUpShowsHours(3600))
        let withHours = NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 3600)
        XCTAssertGreaterThan(withHours, underHourB, "出小时才加宽")
        // 跨档才应触发 panel sync（与 IslandContentView.onChange 同条件）。
        XCTAssertNotEqual(
            FocusTimerFormatting.countUpShowsHours(3599),
            FocusTimerFormatting.countUpShowsHours(3600)
        )
        XCTAssertEqual(
            FocusTimerFormatting.countUpShowsHours(100),
            FocusTimerFormatting.countUpShowsHours(200),
            "同档内秒级跳动不得触发缩扩"
        )
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
