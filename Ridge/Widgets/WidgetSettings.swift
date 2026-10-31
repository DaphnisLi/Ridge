import Combine
import Foundation

/// 用户库小组件的开关、排序、常驻。系统空态不在此列。
@MainActor
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    enum Defaults {
        static let order: [WidgetID] = []
        static let disabled: [WidgetID] = []
        static let pinned: [WidgetID] = []
    }

    private enum Key {
        static let order = "widget.order.v2"
        static let disabled = "widget.disabled.v2"
        static let pinned = "widget.pinned.v2"
    }

    /// 用户排序：越靠前 priority 越高。仅含 `showsInLibrary` 的 id。
    @Published var order: [WidgetID] {
        didSet { UserDefaults.standard.set(order, forKey: Key.order) }
    }

    @Published var disabledIDs: Set<WidgetID> {
        didSet { UserDefaults.standard.set(Array(disabledIDs), forKey: Key.disabled) }
    }

    @Published var pinnedIDs: Set<WidgetID> {
        didSet { UserDefaults.standard.set(Array(pinnedIDs), forKey: Key.pinned) }
    }

    func isEnabled(_ id: WidgetID) -> Bool {
        !disabledIDs.contains(id)
    }

    func setEnabled(_ id: WidgetID, enabled: Bool) {
        if enabled {
            disabledIDs.remove(id)
            if !order.contains(id) {
                order.append(id)
            }
        } else {
            disabledIDs.insert(id)
            pinnedIDs.remove(id)
        }
        AppLog.info("Widget", "开关变更", ["id": id, "enabled": enabled])
    }

    func isPinned(_ id: WidgetID) -> Bool {
        pinnedIDs.contains(id)
    }

    func setPinned(_ id: WidgetID, pinned: Bool) {
        guard let manifest = WidgetRegistry.shared.manifest(for: id),
              manifest.supportsPinning
        else { return }
        if pinned {
            pinnedIDs.insert(id)
            disabledIDs.remove(id)
            if !order.contains(id) { order.append(id) }
        } else {
            pinnedIDs.remove(id)
        }
        AppLog.info("Widget", "常驻变更", ["id": id, "pinned": pinned])
    }

    func priority(for id: WidgetID) -> Int {
        guard let index = order.firstIndex(of: id) else { return 0 }
        return order.count - index
    }

    func move(from offsets: IndexSet, to destination: Int) {
        var next = order
        next.move(fromOffsets: offsets, toOffset: destination)
        order = next
        AppLog.info("Widget", "排序已更新", ["count": next.count])
    }

    func restoreDefaults() {
        order = Defaults.order
        disabledIDs = Set(Defaults.disabled)
        pinnedIDs = Set(Defaults.pinned)
        AppLog.info("Widget", "已恢复小组件默认设置")
    }

    /// 与注册表对齐：只保留库内 widget；新注册的默认追加到末尾并启用。
    func reconcile(with registry: WidgetRegistry) {
        let libraryIDs = registry.libraryManifests.map(\.id)
        let known = Set(libraryIDs)
        order = order.filter { known.contains($0) }
        for id in libraryIDs where !order.contains(id) {
            order.append(id)
        }
        disabledIDs = disabledIDs.intersection(known)
        pinnedIDs = pinnedIDs.intersection(known)
        AppLog.debug("Widget", "设置已与注册表对齐", [
            "library": libraryIDs.count,
            "order": order.count
        ])
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.order) == nil {
            defaults.set(Defaults.order, forKey: Key.order)
        }
        if defaults.object(forKey: Key.disabled) == nil {
            defaults.set(Defaults.disabled, forKey: Key.disabled)
        }
        if defaults.object(forKey: Key.pinned) == nil {
            defaults.set(Defaults.pinned, forKey: Key.pinned)
        }

        order = defaults.stringArray(forKey: Key.order) ?? Defaults.order
        disabledIDs = Set(defaults.stringArray(forKey: Key.disabled) ?? Defaults.disabled)
        pinnedIDs = Set(defaults.stringArray(forKey: Key.pinned) ?? Defaults.pinned)

        AppLog.debug("Widget", "已加载小组件设置", [
            "order": order.count,
            "disabled": disabledIDs.count,
            "pinned": pinnedIDs.count
        ])
    }
}
