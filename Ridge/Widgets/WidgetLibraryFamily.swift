import Foundation

/// 设置「小组件」库扁平展示顺序（不再分提示/实况/面板段）。
/// 上岛闸门仍用 `WidgetLibraryFamily`；本枚举只定库卡先后。
enum WidgetLibraryLayout {
    /// 库页默认顺序：已复制第一；货架紧接专注计时之后；音量倒数第二；项目释放最后。
    static let defaultFlatDisplayOrder: [WidgetID] = [
        "builtin.copiedNotice",
        "builtin.meeting",
        "builtin.aiUsage",
        "builtin.moveReminder",
        "builtin.colorPick",
        "builtin.ocrSelect",
        "builtin.peripheralTip",
        "builtin.media",
        "builtin.focusTimer",
        "system.controlDeck.shelf",
        "system.controlDeck.battery",
        "builtin.worldClock",
        "builtin.stocks",
        "system.controlDeck.volume",
        "system.controlDeck.projects",
    ]

    /// 内容型默认序（不含控制台磁贴；写入 `WidgetSettings.order`）。
    static var defaultContentOrder: [WidgetID] {
        defaultFlatDisplayOrder.filter { !$0.hasPrefix("system.controlDeck.") }
    }

    static func rank(of widgetID: WidgetID) -> Int {
        defaultFlatDisplayOrder.firstIndex(of: widgetID) ?? Int.max
    }
}

/// 上岛闸门分类：提示 / 实况 / 面板（不再驱动设置库分段 UI）。
enum WidgetLibraryFamily: String, CaseIterable, Identifiable, Hashable {
    /// 瞬时提示：触阈/事件冒一下。
    case tip
    /// 有状态时直接上岛（如电量、正在播放）；不再先冒「打开」邀请 tip。
    case live
    /// 常驻操作面板，不靠提示冒出。
    case panel

    var id: String { rawValue }

    /// 历史三段顺序（闸门/测试用；库页已扁平不再按此分段）。
    static let displayOrder: [WidgetLibraryFamily] = [.tip, .live, .panel]

    static func family(for widgetID: WidgetID) -> WidgetLibraryFamily? {
        switch widgetID {
        case "builtin.meeting",
             "builtin.aiUsage",
             "builtin.moveReminder",
             "builtin.colorPick",
             "builtin.ocrSelect",
             "builtin.peripheralTip",
             "builtin.copiedNotice":
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
