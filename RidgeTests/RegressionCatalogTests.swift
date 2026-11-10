import XCTest
@testable import Ridge

/// 对齐 `docs/REGRESSION_CATALOG.md` 中 `recurring: true` 项的自动化锚点。
/// 用例名含 catalog `id`，改 Island / 控制台 / 预览后必须先跑本 target。
final class RegressionCatalogTests: XCTestCase {

    // MARK: - island-hover-retention

    func test_islandHoverRetention_lowerHalfOfLargePanelStaysInRetention() {
        let notch = CGRect(x: 400, y: 900, width: 180, height: 32)
        let panel = CGRect(x: 200, y: 700, width: 660, height: 300)
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: true
        )
        let midLower = CGPoint(x: panel.midX, y: panel.minY + 40)
        XCTAssertTrue(frame.contains(midLower), "大岛下半截必须仍在保展开区")
    }

    func test_islandHoverRetention_rejectsAccidentalShrinkToNotch() {
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: CGSize(width: 660, height: 300),
                measured: CGSize(width: 180, height: 32),
                isExpanded: true,
                allowShrink: false
            )
        )
    }

    func test_islandHoverRetention_shortTipDoesNotPoisonStablePreference() {
        let notch = CGSize(width: 179, height: 32)
        let tip = CGSize(width: 275, height: 68)
        let stable = CGSize(width: 660, height: 300)
        XCTAssertTrue(IslandExpandedPanelPolicy.isTransientShortPanel(tip, notch: notch))
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldPreferStableRetention(
                panel: tip,
                stable: stable,
                notch: notch,
                isExpanded: true
            )
        )
    }

    func test_islandHoverRetention_contentScrollHoldsExpandWithinGrace() {
        let now = Date()
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: now.addingTimeInterval(-0.2),
                now: now
            ),
            "纵滑后宽限内必须保展开（滚一半误收回归）"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: now.addingTimeInterval(-2.0),
                now: now
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: nil,
                now: now
            )
        )
    }

    // MARK: - island-chrome-double-padding

    func test_islandChromeDoublePadding_contentBottomMatchesHorizontal() {
        // 壳层左右与底同值；内容根再加 padding 即叠两层（规则：根视图禁止外圈 padding）。
        XCTAssertEqual(IslandChrome.contentBottom, IslandChrome.contentHorizontal)
        XCTAssertEqual(IslandChrome.horizontalInsetTotal, IslandChrome.contentHorizontal * 2)
        XCTAssertGreaterThan(IslandChrome.contentBottom, 0)
    }

    func test_islandChromeDoublePadding_tokensAreFixed() {
        // 左右 / 底是固定令牌；改数须有意为之，并同步本用例。
        XCTAssertEqual(IslandChrome.contentHorizontal, 14)
        XCTAssertEqual(IslandChrome.contentBottom, 14)
        XCTAssertEqual(IslandChrome.compactTipTopInset, 0)
        XCTAssertEqual(IslandChrome.compactTipBottom, 4)
        XCTAssertEqual(IslandChrome.shortTipBottom, 6)
        XCTAssertLessThan(IslandChrome.compactTipBottom, IslandChrome.contentBottom)
        XCTAssertLessThan(IslandChrome.shortTipBottom, IslandChrome.contentBottom)
    }

    func test_islandChromeDoublePadding_surfaceInsetsLockHorizontalAndBottom() {
        let notchH: CGFloat = 32
        let expanded = IslandChrome.insets(for: .expanded, notchHeight: notchH)
        let wing = IslandChrome.insets(for: .notchWingTip, notchHeight: notchH)
        let shortTip = IslandChrome.insets(for: .shortBelowNotchTip, notchHeight: notchH)
        let notice = IslandChrome.insets(for: .notice, notchHeight: notchH)

        // 所有表面左右边距同一固定令牌。
        for insets in [expanded, wing, shortTip, notice] {
            XCTAssertEqual(insets.horizontal, IslandChrome.contentHorizontal)
        }

        XCTAssertEqual(expanded.bottom, IslandChrome.contentBottom)
        XCTAssertEqual(notice.bottom, IslandChrome.contentBottom)
        // 翼 tip / 短 tip 底距必须用紧凑令牌，禁止误退回 contentBottom（会议 tip 曾叠大底距）。
        XCTAssertEqual(wing.bottom, IslandChrome.compactTipBottom)
        XCTAssertEqual(wing.top, IslandChrome.compactTipTopInset)
        XCTAssertEqual(shortTip.bottom, IslandChrome.shortTipBottom)
        XCTAssertNotEqual(wing.bottom, IslandChrome.contentBottom)
        XCTAssertNotEqual(shortTip.bottom, IslandChrome.contentBottom)
    }

    func test_islandChrome_meetingUsesNotchWing_othersShortCapsule() {
        // 会议：左右翼贴刘海；取色/OCR：矮胶囊短条。
        let meeting = IslandNoticePayload.meetingLead(meetingID: "test-meeting")
        XCTAssertTrue(meeting.usesNotchWingChrome)
        XCTAssertFalse(meeting.usesShortBelowNotchChrome)
        XCTAssertFalse(IslandNoticePayload.colorPickTip.usesNotchWingChrome)
        XCTAssertTrue(IslandNoticePayload.colorPickTip.usesShortBelowNotchChrome)
        XCTAssertFalse(IslandNoticePayload.ocrSelectTip.usesNotchWingChrome)
        XCTAssertTrue(IslandNoticePayload.ocrSelectTip.usesShortBelowNotchChrome)
    }

    func test_meetingLead_keepsExpandedWithoutHover() {
        // 会前提示常驻到入会/结束；移开指针不得 hoverEnd 收岛。
        let meeting = IslandNoticePayload.meetingLead(meetingID: "test-meeting")
        XCTAssertTrue(meeting.keepsExpandedWithoutHover)
        XCTAssertNil(meeting.autoDismissNanoseconds)
    }

    func test_islandOutline_panelKeepsSquareTopCorners() {
        // tip-outline：真岛 / 预览一律上直角；左上 (1,1) 须在路径内。
        let rect = CGRect(x: 0, y: 0, width: 200, height: 40)
        let panel = IslandPanelShape(bottomRadius: 12).path(in: rect)
        XCTAssertTrue(panel.contains(CGPoint(x: 1, y: 1)), "左上应为直角填实")
        XCTAssertTrue(panel.contains(CGPoint(x: 199, y: 1)), "右上应为直角填实")
        XCTAssertFalse(panel.contains(CGPoint(x: 1, y: 39)), "左下应挖空圆角")
        XCTAssertTrue(panel.contains(CGPoint(x: 100, y: 20)))
    }

    func test_islandFocusPolicy_neverStealsOnHoverOrPlainClick() {
        // island-focus-steal：悬停关穿透 / 展开 / 普通点击均不得 activate；穿透开启须交还 key。
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppWhenDisablingClickThrough)
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppOnExpand)
        XCTAssertFalse(IslandFocusPolicy.shouldStealFocusOnPlainIslandMouseDown)
        XCTAssertTrue(IslandFocusPolicy.shouldResignKeyWhenEnablingClickThrough)
    }


    // MARK: - settings-preview-live-data（股票样张条数）

    func test_settingsPreviewLiveData_stockSampleUsesFixedFakePair() {
        // 库卡/详情必须假数据固定两卡，禁止实时行情空态。
        let sample = StockIslandView.previewSnapshots()
        XCTAssertEqual(sample.count, 2, "股票设置预览样张必须固定 2 条")
    }

    // MARK: - volume adaptive height（控制台混音台）

    func test_controlDeckVolumeHeight_adaptsBelowMaxAndCapsAtMax() {
        let maxPanel = NotchGeometry.controlDeckMinHeight
        let sparse = ControlDeckContentSize.volumePanelHeight(deviceCount: 1, appCount: 0)
        let dense = ControlDeckContentSize.volumePanelHeight(deviceCount: 5, appCount: 7)
        XCTAssertLessThan(sparse, maxPanel, "内容少时应矮于原最大高度")
        XCTAssertEqual(dense, maxPanel, "内容多时不得超过原最大高度")
        XCTAssertGreaterThanOrEqual(sparse, 148)
    }

    // MARK: - widget library family（提示 → 实况 → 面板）

    func test_widgetLibraryFamily_displayOrderIsTipLivePanel() {
        XCTAssertEqual(
            WidgetLibraryFamily.displayOrder,
            [.tip, .live, .panel]
        )
    }

    func test_widgetLibraryFamily_mapsKnownWidgets() {
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.meeting"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.media"), .live)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "system.controlDeck.battery"), .live)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "system.controlDeck.volume"), .panel)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.focusTimer"), .panel)
        XCTAssertNil(WidgetLibraryFamily.family(for: "system.empty"))
    }

    func test_widgetLibraryFamily_tipNeverPlacesContentDirectly() {
        XCTAssertFalse(WidgetLibraryFamily.tip.placesContentDirectlyOnIsland)
        XCTAssertFalse(WidgetLibraryFamily.live.placesContentDirectlyOnIsland)
        XCTAssertTrue(WidgetLibraryFamily.panel.placesContentDirectlyOnIsland)
    }

    @MainActor
    func test_widgetLibraryFamily_tipAndClosedLiveRejectedFromContentPage() {
        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testReset")
        LiveIslandGate.shared.close(LiveIslandGate.batteryID, reason: "testReset")
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage("builtin.meeting"))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.batteryID))
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage("builtin.focusTimer"))
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage("system.controlDeck.volume"))
    }
}
