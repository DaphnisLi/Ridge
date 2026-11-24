import Foundation

/// 易被 Agent「修行为时顺手改掉」的视觉令牌登记表。
/// 每个 id 必须有 `RegressionCatalogTests.test_uiStyleLock_<id>` 锚定具体数值；
/// 用户明确要改长相时：改生产令牌 + 同步单测期望值，并在回复里写明改了哪几项。
enum UIStyleLock {
    /// 与 `test_uiStyleLock_*` 后缀一一对应（camelCase）。
    static let pinnedModuleIDs: [String] = [
        "mediaCompactStandby",
        "flushWingGeometry",
        "focusCountUpButton",
        "focusCompactMetrics",
        "islandChromeContent",
        "standbyControlChrome"
    ]

    /// 覆盖闸门：每个 pinned id 须存在对应测试方法名。
    static func expectedTestMethodName(for moduleID: String) -> String {
        "test_uiStyleLock_\(moduleID)"
    }
}
