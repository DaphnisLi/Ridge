import Combine
import Foundation
import SwiftUI

/// 调度 + 生命周期。内容型 widget 按优先级与时间戳竞争；无人争夺时落到系统空态。
@MainActor
final class WidgetRuntime: ObservableObject {
    static let shared = WidgetRuntime()

    @Published private(set) var activeID: WidgetID?
    @Published private(set) var activeTitle: String = ""
    @Published private(set) var isShowingEmpty = true
    @Published private(set) var contentEpoch: Int = 0
    /// 可左右滑动浏览的内容型 widget（已启用且正在争夺），顺序与设置优先级一致。
    @Published private(set) var pageIDs: [WidgetID] = []
    @Published private(set) var pageIndex: Int = 0

    private let registry = WidgetRegistry.shared
    private let settings = WidgetSettings.shared
    private var instances: [WidgetID: any IslandWidget] = [:]
    private var demandTimestamps: [WidgetID: Date] = [:]
    /// 用户滑动选中的页；仍在 pageIDs 内则优先于自动调度。
    private var browseOverrideID: WidgetID?
    private var settingsObservers: Set<AnyCancellable> = []
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        registry.registerBuiltins()
        settings.reconcile(with: registry)

        settings.$order
            .combineLatest(settings.$disabledIDs, settings.$pinnedIDs)
            .dropFirst()
            .sink { [weak self] _, _, _ in
                self?.recompute(reason: "settings")
            }
            .store(in: &settingsObservers)

        recompute(reason: "start")
        AppLog.info("Widget", "Runtime 已启动", [
            "registered": registry.manifests.count,
            "library": registry.libraryManifests.count,
            "active": activeID ?? "nil"
        ])
    }

    func stop() {
        browseOverrideID = nil
        for id in Array(instances.keys) {
            tearDown(id, reason: "stop")
        }
        settingsObservers.removeAll()
        started = false
        AppLog.info("Widget", "Runtime 已停止")
    }

    // MARK: - Demand（供 Context 调用）

    func requestDisplay(_ id: WidgetID) {
        guard registry.manifest(for: id)?.kind == .content else { return }
        if demandTimestamps[id] == nil {
            demandTimestamps[id] = Date()
            AppLog.info("Widget", "申请展示", ["id": id])
        }
        recompute(reason: "request")
    }

    func withdrawDisplay(_ id: WidgetID) {
        guard demandTimestamps.removeValue(forKey: id) != nil else { return }
        AppLog.info("Widget", "撤回展示", ["id": id])
        if browseOverrideID == id {
            browseOverrideID = nil
        }
        recompute(reason: "withdraw")
    }

    func isDemanding(_ id: WidgetID) -> Bool {
        demandTimestamps[id] != nil
    }

    // MARK: - 左右滑动分页

    /// `offset`：+1 下一页（向左滑），-1 上一页（向右滑）。
    func selectPage(offset: Int) {
        guard pageIDs.count >= 2 else { return }
        let count = pageIDs.count
        let next = ((pageIndex + offset) % count + count) % count
        selectPage(at: next)
    }

    func selectPage(at index: Int) {
        guard pageIDs.indices.contains(index) else { return }
        let id = pageIDs[index]
        browseOverrideID = id
        pageIndex = index
        AppLog.info("Widget", "滑动切换小组件", ["id": id, "index": index])
        recompute(reason: "page")
    }

    // MARK: - Access

    func activeView() -> AnyView {
        guard let id = activeID, let widget = instances[id] else {
            return AnyView(Color.clear)
        }
        return widget.makeView()
    }

    func refreshActive() {
        guard let id = activeID, let widget = instances[id] else { return }
        widget.refresh()
        contentEpoch &+= 1
    }

    // MARK: - Schedule

    private struct Candidate {
        let id: WidgetID
        let priority: Int
        let requestedAt: Date
    }

    /// 已启用且正在争夺（requestDisplay）的内容型 widget。
    private func scheduledCandidates() -> [Candidate] {
        var result: [Candidate] = []
        for id in settings.order where settings.isEnabled(id) {
            guard let stamp = demandTimestamps[id] else { continue }
            guard registry.manifest(for: id)?.kind == .content else { continue }
            result.append(Candidate(
                id: id,
                priority: settings.priority(for: id),
                requestedAt: stamp
            ))
        }
        return result.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.requestedAt < $1.requestedAt
        }
    }

    /// 设置页开关 / 拖拽后：确保争夺展示并强制切到该页（立即反映到岛上）。
    func focusForSettings(_ id: WidgetID) {
        guard registry.manifest(for: id)?.kind == .content else { return }
        guard settings.isEnabled(id) else {
            AppLog.debug("Widget", "设置聚焦跳过：未启用", ["id": id])
            return
        }
        _ = ensureInstance(id)
        if demandTimestamps[id] == nil {
            demandTimestamps[id] = Date()
            AppLog.info("Widget", "设置页申请展示", ["id": id])
        }
        browseOverrideID = id
        recompute(reason: "settingsFocus")
    }

    func recompute(reason: String) {
        // 关掉的小组件立刻退出争夺，避免设置里关了岛上还挂着。
        for id in Array(demandTimestamps.keys) where !settings.isEnabled(id) {
            demandTimestamps.removeValue(forKey: id)
            if browseOverrideID == id {
                browseOverrideID = nil
            }
            AppLog.debug("Widget", "已禁用，撤出争夺", ["id": id, "reason": reason])
        }

        // 已启用的内容型先建实例，便于占位/采样类在创建时声明 wantsDisplay。
        for id in settings.order where settings.isEnabled(id) {
            _ = ensureInstance(id)
        }

        // 分页列表：按用户优先级顺序，仅含正在争夺的内容型。
        let pages = settings.order.filter {
            settings.isEnabled($0)
                && demandTimestamps[$0] != nil
                && registry.manifest(for: $0)?.kind == .content
        }
        pageIDs = pages

        if let browse = browseOverrideID, !pages.contains(browse) {
            browseOverrideID = nil
        }

        let chosen: WidgetID
        if let browse = browseOverrideID, pages.contains(browse) {
            chosen = browse
        } else if let top = scheduledCandidates().first {
            chosen = top.id
            browseOverrideID = nil
        } else {
            chosen = SystemWidgetID.empty
            browseOverrideID = nil
        }

        if let idx = pages.firstIndex(of: chosen) {
            pageIndex = idx
        } else {
            pageIndex = 0
        }

        applyActive(chosen, reason: reason)
        reapUnneeded(reason: reason)
    }

    private func applyActive(_ newID: WidgetID, reason: String) {
        let oldID = activeID
        let showingEmpty = newID == SystemWidgetID.empty
        isShowingEmpty = showingEmpty

        guard oldID != newID else {
            if let widget = instances[newID] {
                widget.priority = settings.priority(for: newID)
            }
            return
        }

        if let oldID, let old = instances[oldID] {
            old.onDisappear()
            AppLog.debug("Widget", "onDisappear", ["id": oldID, "reason": reason])
        }

        activeID = newID
        let widget = ensureInstance(newID)
        widget?.priority = settings.priority(for: newID)
        widget?.onAppear()
        widget?.refresh()
        activeTitle = showingEmpty
            ? ""
            : (widget?.title ?? registry.manifest(for: newID)?.displayName ?? newID)
        contentEpoch &+= 1
        AppLog.info("Widget", "切换当前小组件", [
            "id": newID,
            "reason": reason,
            "empty": showingEmpty,
            "priority": settings.priority(for: newID)
        ])
    }

    @discardableResult
    private func ensureInstance(_ id: WidgetID) -> (any IslandWidget)? {
        if let existing = instances[id] { return existing }
        let context = WidgetContextImpl(widgetID: id, runtime: self)
        guard let widget = registry.make(id: id, context: context) else { return nil }
        widget.priority = settings.priority(for: id)
        instances[id] = widget
        // 创建时已 wantsDisplay 的（如占位），同步进争夺表，无需再调 requestDisplay。
        if widget.wantsDisplay, demandTimestamps[id] == nil {
            demandTimestamps[id] = widget.requestedAt
            AppLog.debug("Widget", "创建时即争夺展示", ["id": id])
        }
        return widget
    }

    private func reapUnneeded(reason: String) {
        var keep = Set(settings.pinnedIDs.filter { settings.isEnabled($0) })
        if let activeID { keep.insert(activeID) }
        keep.insert(SystemWidgetID.empty)
        keep.formUnion(demandTimestamps.keys.filter { settings.isEnabled($0) })
        for id in Array(instances.keys) where !keep.contains(id) {
            tearDown(id, reason: reason)
        }
    }

    private func tearDown(_ id: WidgetID, reason: String) {
        guard id != SystemWidgetID.empty || reason == "stop" else { return }
        guard let widget = instances.removeValue(forKey: id) else { return }
        if activeID == id {
            widget.onDisappear()
            activeID = nil
            activeTitle = ""
            isShowingEmpty = true
        }
        AppLog.debug("Widget", "销毁实例", ["id": id, "reason": reason])
    }
}
