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
}
