import XCTest
@testable import Ridge

/// 钉死 `LockedInvariants`：未授权改锁定文件时，数值漂移会红。
final class LockedInvariantsTests: XCTestCase {
    func test_lockedInvariants_lockIDStable() {
        XCTAssertEqual(LockedInvariants.lockID, "ridge.locked-invariants.v2")
    }

    func test_lockedInvariants_hoverRetentionFloorAndPads() {
        let notch = CGSize(width: 179, height: 32)
        let floor = LockedInvariants.HoverRetention.expandedRetentionFloor(notch: notch)
        XCTAssertEqual(floor.width, 320, accuracy: 0.5)
        XCTAssertEqual(floor.height, 160, accuracy: 0.5)
        XCTAssertEqual(LockedInvariants.HoverRetention.accidentalShrinkThreshold, 28, accuracy: 0.01)
        XCTAssertEqual(LockedInvariants.HoverRetention.contentScrollHoldGrace, 0.55, accuracy: 0.001)
        XCTAssertEqual(LockedInvariants.HoverRetention.collapsedInteractivePadX, 32, accuracy: 0.01)
        XCTAssertEqual(LockedInvariants.HoverRetention.retentionPanelPad, 16, accuracy: 0.01)
        XCTAssertEqual(LockedInvariants.HoverRetention.retentionPanelBottomExtra, 20, accuracy: 0.01)
    }

    func test_lockedInvariants_shortWidePickingAlwaysFloors() {
        let notch = CGSize(width: 179, height: 32)
        let picking = CGSize(width: 447, height: 73)
        let resolved = LockedInvariants.HoverRetention.resolvedRetentionPanelSize(
            panel: picking,
            stable: .zero,
            notch: notch,
            isExpanded: true
        )
        let floor = LockedInvariants.HoverRetention.expandedRetentionFloor(notch: notch)
        XCTAssertGreaterThanOrEqual(resolved.height, floor.height - 0.5)
        XCTAssertGreaterThanOrEqual(resolved.width, picking.width - 0.5)
    }

    func test_lockedInvariants_policyForwardsHoverRetention() {
        let notch = CGSize(width: 179, height: 32)
        let panel = CGSize(width: 447, height: 73)
        let a = LockedInvariants.HoverRetention.resolvedRetentionPanelSize(
            panel: panel,
            stable: .zero,
            notch: notch,
            isExpanded: true
        )
        let b = IslandExpandedPanelPolicy.resolvedRetentionPanelSize(
            panel: panel,
            stable: .zero,
            notch: notch,
            isExpanded: true
        )
        XCTAssertEqual(a.width, b.width, accuracy: 0.01)
        XCTAssertEqual(a.height, b.height, accuracy: 0.01)
        XCTAssertEqual(
            IslandExpandedPanelPolicy.accidentalShrinkThreshold,
            LockedInvariants.HoverRetention.accidentalShrinkThreshold,
            accuracy: 0.01
        )
    }

    func test_lockedInvariants_noticeChannelAndTiming() {
        XCTAssertEqual(LockedInvariants.Notice.widgetID, "system.islandNotice")
        XCTAssertEqual(LockedInvariants.Notice.emptyWidgetID, "system.empty")
        XCTAssertEqual(SystemWidgetID.islandNotice, LockedInvariants.Notice.widgetID)
        XCTAssertEqual(SystemWidgetID.empty, LockedInvariants.Notice.emptyWidgetID)
        XCTAssertEqual(LockedInvariants.Notice.standardDisplayNanoseconds, 3_000_000_000)
        XCTAssertEqual(
            IslandNoticeAutoDismissPolicy.standardNanoseconds,
            LockedInvariants.Notice.standardDisplayNanoseconds
        )
        XCTAssertEqual(
            LockedInvariants.PriorityGrade.gradeDChannelID,
            LockedInvariants.Notice.widgetID
        )
    }

    func test_lockedInvariants_settingsBlocksOnlyDesignSticky() {
        XCTAssertTrue(
            LockedInvariants.Notice.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: false,
                designSticky: true
            )
        )
        XCTAssertFalse(
            LockedInvariants.Notice.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: false,
                designSticky: false
            )
        )
        XCTAssertEqual(
            IslandExpandedPanelPolicy.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: false,
                designSticky: true
            ),
            LockedInvariants.Notice.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: false,
                designSticky: true
            )
        )
    }

    func test_lockedInvariants_focusNeverStealsByDefault() {
        XCTAssertFalse(LockedInvariants.Focus.shouldActivateAppOnExpand)
        XCTAssertFalse(LockedInvariants.Focus.shouldActivateAppWhenDisablingClickThrough)
        XCTAssertFalse(LockedInvariants.Focus.shouldActivateAppOnPlainIslandMouseDown)
        XCTAssertTrue(LockedInvariants.Focus.shouldMakeKeyOnPlainIslandMouseDown)
        XCTAssertTrue(LockedInvariants.Focus.shouldResignKeyWhenEnablingClickThrough)
        XCTAssertEqual(
            IslandFocusPolicy.shouldActivateAppOnExpand,
            LockedInvariants.Focus.shouldActivateAppOnExpand
        )
    }

    func test_lockedInvariants_chromeTokensMatchIslandChrome() {
        XCTAssertEqual(IslandChrome.contentHorizontal, LockedInvariants.Chrome.contentHorizontal, accuracy: 0.01)
        XCTAssertEqual(IslandChrome.preparedWingWidth, LockedInvariants.Chrome.preparedWingWidth, accuracy: 0.01)
        XCTAssertEqual(
            IslandChrome.preparedPeripheralWingWidth,
            LockedInvariants.Chrome.preparedPeripheralWingWidth,
            accuracy: 0.01
        )
        XCTAssertEqual(
            IslandChrome.notchRightOrbDiameter,
            LockedInvariants.Chrome.notchRightOrbDiameter,
            accuracy: 0.01
        )
        XCTAssertEqual(
            IslandChrome.notchRightOrbAutoDismissNanoseconds,
            LockedInvariants.Chrome.notchRightOrbAutoDismissNanoseconds
        )
        XCTAssertEqual(IslandChrome.dualFlushLeftWingWidth, LockedInvariants.Chrome.dualFlushLeftWingWidth, accuracy: 0.01)
        XCTAssertEqual(IslandChrome.dualFlushNotchUnderlap, LockedInvariants.Chrome.dualFlushNotchUnderlap, accuracy: 0.01)
        let dual = IslandChrome.insets(for: .dualFlush, notchHeight: 32)
        XCTAssertEqual(dual.top, LockedInvariants.Chrome.dualFlushInsetTop, accuracy: 0.01)
        XCTAssertEqual(dual.bottom, LockedInvariants.Chrome.dualFlushInsetBottom, accuracy: 0.01)
        XCTAssertEqual(dual.horizontal, LockedInvariants.Chrome.dualFlushInsetHorizontal, accuracy: 0.01)
    }

    func test_lockedInvariants_copiedNoticeContracts() {
        XCTAssertTrue(LockedInvariants.CopiedNotice.isCopiedTipID("copy.text.uuid"))
        XCTAssertFalse(LockedInvariants.CopiedNotice.isCopiedTipID("ram-1"))
        XCTAssertEqual(LockedInvariants.CopiedNotice.dedupInterval, 2.0, accuracy: 0.01)
        XCTAssertTrue(LockedInvariants.CopiedNotice.mustDeliverDespiteDesignSticky)
        XCTAssertFalse(LockedInvariants.CopiedNotice.holdsWhileHovering)
        XCTAssertTrue(LockedInvariants.CopiedNotice.dualFlushForbidsGeometryReader)
        XCTAssertEqual(LockedInvariants.CopiedNotice.widgetID, "builtin.copiedNotice")
    }

    func test_lockedInvariants_mediaBlocksExpandDuringFocusPicking() {
        XCTAssertTrue(
            LockedInvariants.Media.shouldBlockMediaExpand(
                focusIsPicking: true,
                activePageIsFocusTimer: true
            )
        )
        XCTAssertFalse(
            LockedInvariants.Media.shouldBlockMediaExpand(
                focusIsPicking: false,
                activePageIsFocusTimer: true
            )
        )
        XCTAssertFalse(LockedInvariants.Media.shouldOpenMediaOnTrailingFocusWing())
        XCTAssertFalse(LockedInvariants.Media.expandedPanelIsResident)
        XCTAssertTrue(
            MediaFocusPickingGate.shouldBlockMediaExpand(
                focusPhase: .picking,
                activePageID: LockedInvariants.Media.focusTimerWidgetID
            )
        )
    }

    func test_lockedInvariants_focusTimerCompletedKeepAndMeetingJoin() {
        XCTAssertTrue(LockedInvariants.FocusTimer.keepsExpandedWithoutHover(phaseIsCompleted: true))
        XCTAssertFalse(LockedInvariants.FocusTimer.keepsExpandedWithoutHover(phaseIsCompleted: false))
        XCTAssertTrue(LockedInvariants.FocusTimer.completedPanelHeightEqualsNotch)
        XCTAssertTrue(LockedInvariants.FocusTimer.countUpButtonEntireCapsuleIsHitTarget)

        XCTAssertTrue(
            LockedInvariants.Meeting.shouldRejectRepublish(
                meetingID: "m1",
                dismissedAfterJoinID: "m1"
            )
        )
        XCTAssertFalse(
            LockedInvariants.Meeting.shouldRejectRepublish(
                meetingID: "m1",
                dismissedAfterJoinID: "m2"
            )
        )
        XCTAssertTrue(
            LockedInvariants.Meeting.isLikelyCalendarEventPage(
                host: "calendar.google.com",
                path: "/event",
                absolute: "https://calendar.google.com/event"
            )
        )
        XCTAssertFalse(
            LockedInvariants.Meeting.isLikelyCalendarEventPage(
                host: "zoom.us",
                path: "/j/123",
                absolute: "https://zoom.us/j/123"
            )
        )
        XCTAssertTrue(
            MeetingLinkDetector.isLikelyCalendarEventPage(
                URL(string: "https://outlook.office.com/calendar/item/1")!
            )
        )
    }

    func test_lockedInvariants_layoutMatrixMatchesSlotPolicy() {
        var slots = IslandNoticeSlots()
        slots.mediaResident = true
        slots.focusResident = true
        let a = LockedInvariants.LayoutMatrix.resolvedLayout(slots)
        let b = IslandNoticeSlotPolicy.resolvedLayout(slots)
        XCTAssertEqual(a, b)
        if case .dual(let left, let right) = a {
            XCTAssertEqual(left, .media)
            XCTAssertEqual(right, .focus)
        } else {
            XCTFail("期望左音乐右专注")
        }

        slots = IslandNoticeSlots()
        slots.downloadResident = true
        slots.focusResident = true
        let down = LockedInvariants.LayoutMatrix.resolvedLayout(slots)
        XCTAssertEqual(down, IslandNoticeSlotPolicy.resolvedLayout(slots))
        if case .dual(let left, let right) = down {
            XCTAssertEqual(left, .download)
            XCTAssertEqual(right, .focus)
        } else {
            XCTFail("期望左下载右计时")
        }
    }

    @MainActor
    func test_lockedInvariants_previewContracts() {
        XCTAssertTrue(LockedInvariants.Preview.tipPreviewHugsContent)
        XCTAssertTrue(LockedInvariants.Preview.forbidDisabledModifier)
        XCTAssertTrue(LockedInvariants.Preview.tipOutlineIsPanel)
        XCTAssertEqual(SettingsIslandPreviewWidth.library, LockedInvariants.Preview.libraryWidth, accuracy: 0.01)
        XCTAssertEqual(SettingsIslandPreviewWidth.tipBarHeight, LockedInvariants.Preview.tipBarHeight, accuracy: 0.01)
        let hugs = WidgetSamplePreview.tipPreviewHugsContent
        XCTAssertEqual(hugs, LockedInvariants.Preview.tipPreviewHugsContent)
        XCTAssertTrue(LockedInvariants.Preview.outlineIsCircle(widgetID: LockedInvariants.CopiedNotice.widgetID))
        XCTAssertFalse(LockedInvariants.Preview.outlineIsCircle(widgetID: "builtin.meeting"))
        XCTAssertEqual(
            IslandExpandedPanelPolicy.postDownloadOpenHoverSuppress,
            LockedInvariants.Download.postOpenHoverSuppress,
            accuracy: 0.01
        )
    }
}
