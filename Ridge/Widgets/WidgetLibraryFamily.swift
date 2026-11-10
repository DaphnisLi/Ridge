import Foundation

/// 小组件库三段分类：提示 → 实况 → 面板（设置页展示顺序）。
enum WidgetLibraryFamily: String, CaseIterable, Identifiable, Hashable {
    /// 瞬时提示：触阈/事件冒一下。
    case tip
    /// 有状态提示，点提示可进面板（如电量、正在播放）。
    case live
    /// 常驻操作面板，不靠提示冒出。
    case panel

    var id: String { rawValue }

    /// 库页自上而下顺序。
    static let displayOrder: [WidgetLibraryFamily] = [.tip, .live, .panel]

    static func family(for widgetID: WidgetID) -> WidgetLibraryFamily? {
        switch widgetID {
        case "builtin.meeting",
             "builtin.aiUsage",
             "builtin.moveReminder",
             "builtin.colorPick",
             "builtin.ocrSelect":
            return .tip
        case "system.controlDeck.battery",
             "builtin.media":
            return .live
        case "system.controlDeck.volume",
             "system.controlDeck.projects",
             "system.controlDeck.shelf",
             "builtin.focusTimer",
             "builtin.worldClock",
             "builtin.stocks":
            return .panel
        default:
            return nil
        }
    }

    static func family(forDeckModuleID id: String) -> WidgetLibraryFamily? {
        family(for: "system.controlDeck.\(id)")
    }
}
