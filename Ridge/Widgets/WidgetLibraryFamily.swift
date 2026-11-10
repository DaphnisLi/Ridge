import Foundation

/// 小组件库三段分类：提示 → 实况 → 面板（设置页展示顺序）。
enum WidgetLibraryFamily: String, CaseIterable, Identifiable, Hashable {
    /// 瞬时提示：触阈/事件冒一下。
    case tip
    /// 有状态时直接上岛（如电量、正在播放）；不再先冒「打开」邀请 tip。
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

    /// 开启后可直接占岛分页（仅面板类）。
    var placesContentDirectlyOnIsland: Bool {
        self == .panel
    }

    /// 该 id 当前是否允许作为内容页上岛。
    @MainActor
    static func allowsIslandContentPage(_ widgetID: WidgetID) -> Bool {
        switch family(for: widgetID) {
        case .tip:
            return false
        case .live:
            return LiveIslandGate.shared.isOpened(widgetID)
        case .panel, .none:
            return true
        }
    }

    /// 控制台模块启用后是否立刻进分页（实况须已 admit）。
    @MainActor
    static func controlDeckPaneAppearsWhenEnabled(_ pane: ControlDeckSettings.Pane) -> Bool {
        allowsIslandContentPage(pane.pageID)
    }
}
