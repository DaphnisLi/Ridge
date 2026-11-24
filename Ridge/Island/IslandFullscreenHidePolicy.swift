import Foundation

/// 全屏 / 系统启动台遮罩时是否隐藏岛。
///
/// Dock「App」（`Apps.app` / 旧 Launchpad）与 Siri 启动台层级低于 Ridge 岛窗；
/// 若不让路，用户会感觉点 Dock「App」没反应。此路径**不受**「全屏时禁用灵动岛」开关影响。
enum IslandFullscreenHidePolicy {
    /// - Parameters:
    ///   - appFullscreen: 前台 App 绿钮原生全屏
    ///   - systemOverlay: Dock App / Siri / Launchpad 系统遮罩
    ///   - hideInFullscreenSetting: 设置「全屏时禁用灵动岛」
    static func shouldHideIsland(
        appFullscreen: Bool,
        systemOverlay: Bool,
        hideInFullscreenSetting: Bool
    ) -> Bool {
        if systemOverlay { return true }
        return appFullscreen && hideInFullscreenSetting
    }
}
