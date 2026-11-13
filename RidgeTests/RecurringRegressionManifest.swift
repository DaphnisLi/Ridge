import Foundation
import ObjectiveC
import XCTest
@testable import Ridge

/// `docs/REGRESSION_CATALOG.md` 顶部「重复出现问题」的机器可读清单。
/// Agent 改完代码后只强制跑与此表相关的自动化；`occurrences == 1` 不强制写/跑测。
enum RecurringRegressionManifest {
    struct Entry: Equatable {
        /// 与 catalog `id` 完全一致。
        let id: String
        /// `RegressionCatalogTests` / `IslandExpandedPanelPolicyTests` 中用例名前缀（至少命中一条）。
        let testNamePrefixes: [String]
    }

    /// 权威列表：增删 recurring 项时同步改此处与 `docs/REGRESSION_CATALOG.md`。
    static let all: [Entry] = [
        Entry(
            id: "island-hover-retention",
            testNamePrefixes: [
                "test_islandHoverRetention_",
                "test_islandHoverExpand_",
                "testExpandedRetentionFloor",
                "testRejectsAccidentalShrink"
            ]
        ),
        Entry(
            id: "island-chrome-double-padding",
            testNamePrefixes: [
                "test_islandChromeDoublePadding_",
                "test_islandChrome_"
            ]
        ),
        Entry(
            id: "settings-preview-live-data",
            testNamePrefixes: ["test_settingsPreviewLiveData_"]
        ),
        Entry(
            id: "shelf-copied-notice-miss",
            testNamePrefixes: [
                "test_shelfCopiedNoticeMiss_",
                "testAllowsWingTipToShortCopied"
            ]
        ),
        Entry(
            id: "tip-outline-panel",
            testNamePrefixes: [
                "test_islandOutline_panel",
                "test_tipOutlinePanel_"
            ]
        ),
        Entry(
            id: "island-focus-steal",
            testNamePrefixes: [
                "test_islandFocusPolicy_",
                "test_islandFocusSteal_"
            ]
        ),
        Entry(
            id: "library-island-stage-stretch",
            testNamePrefixes: [
                "test_libraryIslandStageStretch_",
                "test_compactIsland_"
            ]
        ),
        Entry(
            id: "settings-preview-island-appearance",
            testNamePrefixes: ["test_settingsPreviewIslandAppearance_"]
        ),
        Entry(
            id: "shelf-magnetic-staging-double",
            testNamePrefixes: [
                "test_shelfFileDragCancel_",
                "test_shelfMagneticStagingDouble_"
            ]
        )
    ]

    static var ids: [String] { all.map(\.id) }

    /// 从 XCTestCase 子类收集 `test*` 实例方法名。
    static func testMethodNames(in type: AnyClass) -> [String] {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(type, &count) else { return [] }
        defer { free(list) }
        var names: [String] = []
        for i in 0..<Int(count) {
            let sel = method_getName(list[i])
            let name = NSStringFromSelector(sel)
            if name.hasPrefix("test") {
                names.append(name)
            }
        }
        return names
    }

    /// 合并 recurring 相关测试类上的全部 `test*` 名。
    static func discoveredRecurringSuiteMethodNames() -> [String] {
        var names = testMethodNames(in: RegressionCatalogTests.self)
        names.append(contentsOf: testMethodNames(in: IslandExpandedPanelPolicyTests.self))
        names.append(contentsOf: testMethodNames(in: RecurringRegressionCoverageTests.self))
        return names
    }

    static func entry(id: String) -> Entry? {
        all.first { $0.id == id }
    }
}
