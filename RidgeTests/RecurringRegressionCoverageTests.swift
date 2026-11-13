import ObjectiveC
import SwiftUI
import XCTest
@testable import Ridge

/// recurring 覆盖闸门 + 补强断言。改完代码后由 `scripts/test-recurring.sh` 强制执行。
final class RecurringRegressionCoverageTests: XCTestCase {

    /// 目录里每一个 `recurring: true` id 都必须至少有一条锚定用例。
    func test_recurringManifest_everyCatalogIdHasAnchoredTest() {
        let methods = RecurringRegressionManifest.discoveredRecurringSuiteMethodNames()
        XCTAssertFalse(methods.isEmpty, "未发现任何 recurring 测试方法")

        for entry in RecurringRegressionManifest.all {
            let hit = entry.testNamePrefixes.contains { prefix in
                methods.contains { $0.hasPrefix(prefix) }
            }
            XCTAssertTrue(
                hit,
                "catalog id=\(entry.id) 缺少自动化：期望前缀 \(entry.testNamePrefixes.joined(separator: ", "))；现有 \(methods.count) 条 test*"
            )
        }
    }

    /// 防 Manifest 与文档顶部表脱节：id 数量与已知表一致（9）。
    func test_recurringManifest_matchesDocumentedTableCount() {
        XCTAssertEqual(
            RecurringRegressionManifest.all.count,
            9,
            "增减 recurring 项时同步改 Manifest、REGRESSION_CATALOG 顶部表与本断言"
        )
        let unique = Set(RecurringRegressionManifest.ids)
        XCTAssertEqual(unique.count, RecurringRegressionManifest.all.count, "recurring id 不得重复")
    }

    // MARK: - tip-outline-panel 补强

    func test_tipOutlinePanel_outlineShapeKeepsSquareTopCorners() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 40)
        let path = IslandOutlineShape(style: .panel, bottomRadius: 12).path(in: rect)
        XCTAssertTrue(path.contains(CGPoint(x: 1, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 199, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 39)))
    }

    // MARK: - island-focus-steal 补强

    func test_islandFocusSteal_makeKeyWithoutActivateAndDirectHitContract() {
        // 矫枉后仍须 makeKey，否则岛上按钮首击失灵；禁止 activate 抢前台。
        XCTAssertTrue(IslandFocusPolicy.shouldMakeKeyOnPlainIslandMouseDown)
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppOnPlainIslandMouseDown)
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppOnExpand)
        XCTAssertTrue(IslandFocusPolicy.shouldResignKeyWhenEnablingClickThrough)
        // 混音台等自绘热区依赖 IslandDirectHitTarget；协议必须仍存在于模块内。
        let _: IslandDirectHitTarget.Type = IslandDirectHitTargetProbe.self
    }

    // MARK: - library-island-stage-stretch 补强

    func test_libraryIslandStageStretch_focusRingMatchesMediaArtwork() {
        // 专注待命环须与媒体封面同档（22），禁止再抬到 24+ 把预览岛撑高。
        XCTAssertEqual(FocusTimerCompactMetrics.progressRingDiameter, 22, accuracy: 0.5)
        XCTAssertEqual(SettingsIslandPreviewWidth.library, 290)
        XCTAssertEqual(SettingsIslandPreviewWidth.tipBarHeight, 30)
    }

    // MARK: - settings-preview-island-appearance 补强

    func test_settingsPreviewIslandAppearance_visibleTopInsetPositive() {
        // 预览展开顶距须用可见 inset（无刘海盲区），且 >0。
        let inset = IslandChrome.previewExpandedVisibleTopInset(notchHeight: 32)
        XCTAssertGreaterThan(inset, 0)
        XCTAssertLessThan(
            inset,
            IslandChrome.expandedTopInset(notchHeight: 32) + 0.5,
            "预览顶距不应大于含盲区的真岛顶距"
        )
    }
}

/// 仅用于确认 `IslandDirectHitTarget` 可被测试模块引用（协议未删）。
private final class IslandDirectHitTargetProbe: NSObject, IslandDirectHitTarget {}
