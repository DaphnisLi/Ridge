import Combine
import Foundation

/// 用户库小组件的开关、排序、常驻。系统空态与控制台不在此列。
@MainActor
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    enum Defaults {
        static var order: [WidgetID] { WidgetLibraryLayout.defaultContentOrder }
        /// 权限按需：库内小组件默认全部关闭，打开开关时再申请。
        static var disabled: [WidgetID] { WidgetLibraryLayout.defaultContentOrder }
        static let pinned: [WidgetID] = []
    }

    private enum Key {
        static let order = "widget.order.v2"
        static let disabled = "widget.disabled.v2"
        static let pinned = "widget.pinned.v2"
        /// 旧组合页键，仅启动时交给 ControlDeck 迁移后清理。
        static let comboPagesLegacy = "widget.comboPages.v1"
        static let pageGroupsLegacy = "widget.pageGroups.v1"
        /// 库页扁平默认序（一次性迁移；升 v 号会再写一遍 canonical）。
        static let flatLibraryOrderMigrated = "widget.libraryFlatOrder.v4"
        /// 小组件默认全关（升 v 号再强制一次）。
        static let defaultOffMigrated = "widget.defaultOff.v2"
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
        if id == ClipboardCopiedNoticeGate.widgetID {
            ClipboardCopiedNoticeGate.syncClipboardMonitoring(reason: "copiedTipToggle")
        }
        // 每次打开开关都校验并申请该能力所需权限（无需求则空操作）。
        if enabled {
            if id == "builtin.moveReminder" {
                MoveReminderSession.shared.start()
            }
            if id == "builtin.aiUsage" {
                AIUsageSession.shared.start()
            }
            Task { @MainActor in
                await WidgetPermissionGate.ensureOnEnable(widgetID: id)
            }
        } else if id == "builtin.moveReminder" {
            MoveReminderSession.shared.stop()
        }
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

    func gridSize(for id: WidgetID) -> WidgetGridSize {
        WidgetRegistry.shared.manifest(for: id)?.defaultGridSize ?? .oneByOne
    }

    func move(from offsets: IndexSet, to destination: Int) {
        var next = order
        next.move(fromOffsets: offsets, toOffset: destination)
        order = next
        AppLog.info("Widget", "排序已更新", ["count": next.count])
    }

    @discardableResult
    func move(draggedID: WidgetID, onto targetID: WidgetID) -> Bool {
        guard draggedID != targetID,
              let from = order.firstIndex(of: draggedID),
              let to = order.firstIndex(of: targetID),
              from != to
        else { return false }

        var next = order
        next.swapAt(from, to)
        order = next
        AppLog.debug("Widget", "拖拽交换", [
            "from": draggedID,
            "onto": targetID,
            "fromIndex": from,
            "toIndex": to
        ])
        return true
    }

    func restoreDefaults() {
        order = Defaults.order
        disabledIDs = Set(Defaults.disabled)
        pinnedIDs = Set(Defaults.pinned)
        AppLog.info("Widget", "已恢复小组件默认设置")
    }

    /// 与注册表对齐；缺失 id 按扁平默认序插入。
    func reconcile(with registry: WidgetRegistry) {
        let libraryIDs = registry.libraryManifests.map(\.id)
        let known = Set(libraryIDs)
        order = order.filter { known.contains($0) }
        for id in WidgetLibraryLayout.defaultContentOrder where known.contains(id) && !order.contains(id) {
            insertInCanonicalPosition(id)
        }
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

    /// 按 `WidgetLibraryLayout.defaultContentOrder` 插入缺失项。
    private func insertInCanonicalPosition(_ id: WidgetID) {
        guard !order.contains(id) else { return }
        let canonical = WidgetLibraryLayout.defaultContentOrder
        guard let targetRank = canonical.firstIndex(of: id) else {
            order.append(id)
            return
        }
        for (index, existing) in order.enumerated() {
            let existingRank = canonical.firstIndex(of: existing) ?? Int.max
            if existingRank > targetRank {
                order.insert(id, at: index)
                return
            }
        }
        order.append(id)
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

        // 取消三段分类：一次性写入扁平默认内容序（未知 id 仍接在末尾）。
        if defaults.object(forKey: Key.flatLibraryOrderMigrated) == nil {
            let previous = defaults.stringArray(forKey: Key.order) ?? []
            let canonical = WidgetLibraryLayout.defaultContentOrder
            let extras = previous.filter { !canonical.contains($0) }
            let migrated = canonical + extras
            defaults.set(migrated, forKey: Key.order)
            defaults.set(true, forKey: Key.flatLibraryOrderMigrated)
            AppLog.info("Widget", "已迁移扁平库默认排序", [
                "count": migrated.count,
                "first": migrated.first ?? ""
            ])
        }

        let loadedOrder = defaults.stringArray(forKey: Key.order) ?? Defaults.order
        order = loadedOrder
        disabledIDs = Set(defaults.stringArray(forKey: Key.disabled) ?? Defaults.disabled)
        pinnedIDs = Set(defaults.stringArray(forKey: Key.pinned) ?? Defaults.pinned)

        if !defaults.bool(forKey: Key.defaultOffMigrated) {
            let allOff = Set(WidgetLibraryLayout.defaultContentOrder)
            disabledIDs = allOff
            pinnedIDs = []
            defaults.set(Array(disabledIDs), forKey: Key.disabled)
            defaults.set(true, forKey: Key.defaultOffMigrated)
            AppLog.info("Widget", "已迁移为小组件默认全关", [
                "version": Key.defaultOffMigrated,
                "disabled": disabledIDs.count
            ])
        }

        // 确保 ControlDeck 迁移先跑（清掉旧 combo 键）。
        _ = ControlDeckSettings.shared
        defaults.removeObject(forKey: Key.comboPagesLegacy)
        defaults.removeObject(forKey: Key.pageGroupsLegacy)

        AppLog.debug("Widget", "已加载小组件设置", [
            "order": order.count,
            "disabled": disabledIDs.count,
            "pinned": pinnedIDs.count
        ])
    }
}
