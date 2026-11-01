import Combine
import Foundation

/// 用户库小组件的开关、排序、常驻、组合页。系统空态不在此列。
@MainActor
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    enum Defaults {
        static let order: [WidgetID] = []
        static let disabled: [WidgetID] = []
        static let pinned: [WidgetID] = []
        static let comboPages: [[WidgetID]] = []
    }

    private enum Key {
        static let order = "widget.order.v2"
        static let disabled = "widget.disabled.v2"
        static let pinned = "widget.pinned.v2"
        /// 用户显式创建的组合页（可为空页）。
        static let comboPages = "widget.comboPages.v1"
        /// 旧版 pageGroups，仅迁移用。
        static let pageGroupsLegacy = "widget.pageGroups.v1"
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

    /// 组合页列表：每项最多占 8 格；未放满也按一行 4 格顺序排布。
    /// 未出现在任何组合页中的小组件各自独占普通页。
    @Published var comboPages: [[WidgetID]] {
        didSet { persistComboPages() }
    }

    /// 设置页「加号」默认写入的组合页下标。
    @Published var activeComboPageIndex: Int = 0

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
            removeFromAllComboPages(id)
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

    func gridSize(for id: WidgetID) -> WidgetGridSize {
        WidgetRegistry.shared.manifest(for: id)?.defaultGridSize ?? .oneByOne
    }

    /// 是否已在某个组合页中。
    func comboPageIndex(containing id: WidgetID) -> Int? {
        comboPages.firstIndex { $0.contains(id) }
    }

    func isInAnyComboPage(_ id: WidgetID) -> Bool {
        comboPageIndex(containing: id) != nil
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

    // MARK: - 组合页

    /// 新建空组合页，并设为加号目标。
    @discardableResult
    func createComboPage() -> Int {
        comboPages.append([])
        let index = comboPages.count - 1
        activeComboPageIndex = index
        AppLog.info("Widget", "新建组合页", ["index": index, "total": comboPages.count])
        return index
    }

    /// 删除组合页；其中的小组件回到各自普通页。
    func deleteComboPage(at index: Int) {
        guard comboPages.indices.contains(index) else { return }
        comboPages.remove(at: index)
        if comboPages.isEmpty {
            activeComboPageIndex = 0
        } else {
            activeComboPageIndex = min(activeComboPageIndex, comboPages.count - 1)
        }
        AppLog.info("Widget", "删除组合页", ["index": index, "remaining": comboPages.count])
    }

    /// 把小组件加入指定组合页（默认当前 active）。装不下 8 格则失败。
    @discardableResult
    func addWidgetToComboPage(_ id: WidgetID, pageIndex: Int? = nil) -> Bool {
        guard order.contains(id) else { return false }
        let index = pageIndex ?? activeComboPageIndex
        guard comboPages.indices.contains(index) else {
            AppLog.warn("Widget", "加入组合页失败：无目标页", ["id": id])
            return false
        }

        if let existing = comboPageIndex(containing: id), existing == index {
            AppLog.debug("Widget", "已在该组合页", ["id": id, "page": index])
            return false
        }

        var pages = normalizedComboPages()
        // 先从其它组合页移除
        for i in pages.indices {
            pages[i].removeAll { $0 == id }
        }
        guard pages.indices.contains(index) else { return false }

        var target = pages[index]
        target.append(id)
        let sizes = target.map { gridSize(for: $0) }
        guard WidgetGridPacker.canFit(sizes) else {
            AppLog.warn("Widget", "加入组合页失败：超过 8 格", [
                "id": id,
                "page": index,
                "count": target.count,
                "cells": sizes.reduce(0) { $0 + $1.cellCount }
            ])
            return false
        }

        pages[index] = target
        comboPages = pages
        activeComboPageIndex = index
        AppLog.info("Widget", "已加入组合页", [
            "id": id,
            "page": index,
            "count": target.count
        ])
        return true
    }

    /// 从组合页移除，回到普通独占页。
    @discardableResult
    func removeWidgetFromComboPage(_ id: WidgetID) -> Bool {
        guard let index = comboPageIndex(containing: id) else { return false }
        var pages = comboPages
        pages[index].removeAll { $0 == id }
        comboPages = pages
        AppLog.info("Widget", "已移出组合页", ["id": id, "page": index])
        return true
    }

    func restoreDefaults() {
        order = Defaults.order
        disabledIDs = Set(Defaults.disabled)
        pinnedIDs = Set(Defaults.pinned)
        comboPages = Defaults.comboPages
        activeComboPageIndex = 0
        AppLog.info("Widget", "已恢复小组件默认设置")
    }

    /// 与注册表对齐。
    func reconcile(with registry: WidgetRegistry) {
        let libraryIDs = registry.libraryManifests.map(\.id)
        let known = Set(libraryIDs)
        order = order.filter { known.contains($0) }
        for id in libraryIDs where !order.contains(id) {
            order.append(id)
        }
        disabledIDs = disabledIDs.intersection(known)
        pinnedIDs = pinnedIDs.intersection(known)
        comboPages = normalizedComboPages().map { $0.filter { known.contains($0) } }
        if !comboPages.isEmpty {
            activeComboPageIndex = min(activeComboPageIndex, comboPages.count - 1)
        } else {
            activeComboPageIndex = 0
        }

        AppLog.debug("Widget", "设置已与注册表对齐", [
            "library": libraryIDs.count,
            "order": order.count,
            "comboPages": comboPages.count
        ])
    }

    /// 去重、只保留 order 内 id；允许空组合页保留。
    func normalizedComboPages() -> [[WidgetID]] {
        var global = Set<WidgetID>()
        return comboPages.map { group in
            uniquePreserveOrder(group.filter { order.contains($0) }).filter { id in
                if global.contains(id) { return false }
                global.insert(id)
                return true
            }
        }
    }

    private func removeFromAllComboPages(_ id: WidgetID) {
        let next = comboPages.map { $0.filter { $0 != id } }
        if next != comboPages {
            comboPages = next
        }
    }

    private func uniquePreserveOrder(_ ids: [WidgetID]) -> [WidgetID] {
        var seen = Set<WidgetID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func persistComboPages() {
        UserDefaults.standard.set(comboPages, forKey: Key.comboPages)
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

        let loadedOrder = defaults.stringArray(forKey: Key.order) ?? Defaults.order
        order = loadedOrder
        disabledIDs = Set(defaults.stringArray(forKey: Key.disabled) ?? Defaults.disabled)
        pinnedIDs = Set(defaults.stringArray(forKey: Key.pinned) ?? Defaults.pinned)

        if let raw = defaults.array(forKey: Key.comboPages) as? [[String]] {
            comboPages = raw
        } else if let legacy = defaults.array(forKey: Key.pageGroupsLegacy) as? [[String]] {
            // 旧版：多组件页迁成组合页；单组件页变回普通独占。
            comboPages = legacy.filter { $0.count > 1 }
            persistComboPages()
            AppLog.info("Widget", "已从旧 pageGroups 迁移组合页", ["count": comboPages.count])
        } else {
            comboPages = Defaults.comboPages
        }

        if !comboPages.isEmpty {
            activeComboPageIndex = 0
        }

        AppLog.debug("Widget", "已加载小组件设置", [
            "order": order.count,
            "disabled": disabledIDs.count,
            "pinned": pinnedIDs.count,
            "comboPages": comboPages.count
        ])
    }
}
