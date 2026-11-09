import Combine
import Foundation
import SwiftUI

/// 调度 + 生命周期。内容型 widget 按优先级与时间戳竞争；同页可多组件网格共存。
@MainActor
final class WidgetRuntime: ObservableObject {
    static let shared = WidgetRuntime()

    /// 当前页主 id（标题 / 兼容旧逻辑）；多组件页取组内优先级最高者。
    @Published private(set) var activeID: WidgetID?
    @Published private(set) var activeTitle: String = ""
    @Published private(set) var isShowingEmpty = true
    @Published private(set) var contentEpoch: Int = 0
    /// 每一页上的小组件 id 列表（仅含正在争夺的）。
    @Published private(set) var pages: [[WidgetID]] = []
    /// 兼容旧调用：每页的「代表」id（组内第一个）。
    @Published private(set) var pageIDs: [WidgetID] = []
    @Published private(set) var pageIndex: Int = 0
    /// 当前页要渲染的 id。
    @Published private(set) var visibleWidgetIDs: [WidgetID] = []
    /// 当前页打包后的占位。
    @Published private(set) var visiblePlacements: [WidgetGridPlacement] = []
    /// 高页（控制台）：岛高为普通页的 2 倍。
    @Published private(set) var isComboPage = false
    /// 当前页是否为控制台（与小组件网格互斥）。
    @Published private(set) var isControlDeckPage = false
    /// 当前页是否为瞬时通知（进程结束等），用贴刘海的矮展开高度。
    @Published private(set) var isTransientNoticePage = false

    private enum StorageKey {
        static let lastBrowsePageID = "widget.runtime.lastBrowsePageID.v1"
    }

    private let registry = WidgetRegistry.shared
    private let settings = WidgetSettings.shared
    private let controlDeck = ControlDeckSettings.shared
    private var instances: [WidgetID: any IslandWidget] = [:]
    private var demandTimestamps: [WidgetID: Date] = [:]
    /// 用户滑动选中的页代表 id；仍在 pageIDs 内则优先于自动调度。
    private var browseOverrideID: WidgetID?
    private var settingsObservers: Set<AnyCancellable> = []
    private var appearedIDs: Set<WidgetID> = []
    private var started = false
    /// 防止 `make` → `requestDisplay` → `recompute` → `ensureInstance` 在写入 `instances` 前重入创建。
    private var creatingIDs: Set<WidgetID> = []

    private init() {}

    /// 记住用户最近停留的内容/控制台页（不含瞬时通知、空态），下次回岛优先恢复。
    private func rememberBrowsePage(_ id: WidgetID) {
        if id == SystemWidgetID.empty || id == SystemWidgetID.islandNotice {
            return
        }
        if registry.manifest(for: id)?.kind == .systemTransient {
            return
        }
        UserDefaults.standard.set(id, forKey: StorageKey.lastBrowsePageID)
        AppLog.debug("Widget", "已记住上次小组件页", ["id": id])
    }

    private func rememberedBrowsePageID() -> WidgetID? {
        UserDefaults.standard.string(forKey: StorageKey.lastBrowsePageID)
    }

    private func shouldRestoreRememberedPage(reason: String) -> Bool {
        // 仅冷启动 / 瞬时通知撤回后恢复。内容型（媒体）撤回不得在岛仍展开时把页拨去计时。
        reason == "start" || reason == "withdrawTransient"
    }

    func start() {
        guard !started else { return }
        started = true
        registry.registerBuiltins()
        settings.reconcile(with: registry)
        // 取色 / OCR 不占岛页，实例会被 reap；快捷键由协调器常驻注册。
        CaptureHotKeyCoordinator.shared.start()

        settings.$order
            .combineLatest(settings.$disabledIDs, settings.$pinnedIDs)
            .dropFirst()
            .sink { [weak self] _ in
                self?.recompute(reason: "settings")
            }
            .store(in: &settingsObservers)

        controlDeck.$isEnabled
            .dropFirst()
            .sink { [weak self] _ in
                self?.recompute(reason: "controlDeck")
            }
            .store(in: &settingsObservers)

        recompute(reason: "start")
        AppLog.info("Widget", "Runtime 已启动", [
            "registered": registry.manifests.count,
            "library": registry.libraryManifests.count,
            "active": activeID ?? "nil",
            "pages": pages.count,
            "controlDeck": controlDeck.isEnabled
        ])
    }

    func stop() {
        browseOverrideID = nil
        for id in Array(instances.keys) {
            tearDown(id, reason: "stop")
        }
        appearedIDs.removeAll()
        settingsObservers.removeAll()
        started = false
        AppLog.info("Widget", "Runtime 已停止")
    }

    // MARK: - Demand（供 Context 调用）

    func requestDisplay(_ id: WidgetID) {
        guard let kind = registry.manifest(for: id)?.kind,
              kind == .content || kind == .systemTransient
        else { return }
        let isNewDemand = demandTimestamps[id] == nil
        if isNewDemand {
            demandTimestamps[id] = Date()
            AppLog.info("Widget", "申请展示", ["id": id, "kind": kind.rawValue])
        }
        // 瞬时通知始终抢页。
        // 内容型首次争夺才切页；若媒体正在占页，专注计时等重建不得把页抢走。
        if kind == .systemTransient {
            browseOverrideID = id
            AppLog.info("Widget", "申请展示已切页", [
                "id": id,
                "kind": kind.rawValue,
                "new": isNewDemand
            ])
        } else if isNewDemand {
            let mediaID = "builtin.media"
            let mediaHoldingPage = demandTimestamps[mediaID] != nil
                && (browseOverrideID == mediaID || activeID == mediaID)
            if mediaHoldingPage, id != mediaID {
                AppLog.info("Widget", "申请展示未切页：媒体正在展示", [
                    "id": id,
                    "active": activeID ?? "nil"
                ])
            } else {
                browseOverrideID = id
                AppLog.info("Widget", "申请展示已切页", [
                    "id": id,
                    "kind": kind.rawValue,
                    "new": isNewDemand
                ])
            }
        }
        recompute(reason: "request")
    }

    func withdrawDisplay(_ id: WidgetID) {
        guard demandTimestamps.removeValue(forKey: id) != nil else { return }
        let wasTransient = registry.manifest(for: id)?.kind == .systemTransient
        AppLog.info("Widget", "撤回展示", [
            "id": id,
            "transient": wasTransient
        ])
        if browseOverrideID == id {
            browseOverrideID = nil
        }
        // 瞬时通知撤回才恢复上次浏览页；媒体撤回若仍展开，避免立刻跳到专注计时。
        recompute(reason: wasTransient ? "withdrawTransient" : "withdrawContent")
    }

    func isDemanding(_ id: WidgetID) -> Bool {
        demandTimestamps[id] != nil
    }

    // MARK: - 左右滑动分页

    /// `offset`：+1 下一页（向左滑），-1 上一页（向右滑）。瞬时通知页禁止切换。
    func selectPage(offset: Int) {
        guard !isTransientNoticePage else {
            AppLog.debug("Widget", "瞬时通知页禁止左右滑动")
            return
        }
        guard pageIDs.count >= 2 else { return }
        let count = pageIDs.count
        let next = ((pageIndex + offset) % count + count) % count
        selectPage(at: next)
    }

    func selectPage(at index: Int) {
        guard !isTransientNoticePage else {
            AppLog.debug("Widget", "瞬时通知页禁止左右滑动", ["index": index])
            return
        }
        guard pageIDs.indices.contains(index) else { return }
        let id = pageIDs[index]
        browseOverrideID = id
        rememberBrowsePage(id)
        pageIndex = index
        AppLog.info("Widget", "滑动切换小组件页", [
            "id": id,
            "index": index,
            "widgets": pages[index].count
        ])
        recompute(reason: "page")
    }

    // MARK: - Access

    func view(for id: WidgetID) -> AnyView {
        guard let widget = instances[id] else {
            return AnyView(Color.clear)
        }
        return widget.makeView()
    }

    /// 兼容旧单组件宿主。
    func activeView() -> AnyView {
        guard let id = activeID else { return AnyView(Color.clear) }
        return view(for: id)
    }

    func refreshActive() {
        for id in visibleWidgetIDs {
            instances[id]?.refresh()
        }
        contentEpoch &+= 1
    }

    /// 设置里打开 / 预览控制台：切到指定（或当前）控制台模块高页。
    func focusControlDeck(pane: ControlDeckSettings.Pane? = nil) {
        guard controlDeck.isEnabled else {
            AppLog.debug("Widget", "聚焦控制台跳过：未开启")
            return
        }
        let target = pane ?? controlDeck.activePane
        let pageID = ControlDeckSettings.pageID(for: target)
        if controlDeck.enabledPanes.contains(target) {
            browseOverrideID = pageID
            rememberBrowsePage(pageID)
        } else if let first = controlDeck.enabledPanes.first {
            browseOverrideID = first.pageID
            rememberBrowsePage(first.pageID)
        } else {
            browseOverrideID = nil
        }
        recompute(reason: "controlDeckFocus")
        AppLog.info("Widget", "聚焦控制台", ["pane": target.rawValue, "page": browseOverrideID ?? "nil"])
    }

    // MARK: - Schedule

    private struct Candidate {
        let id: WidgetID
        let priority: Int
        let requestedAt: Date
    }

    /// 已启用且正在争夺的内容型 + 瞬时系统通知。
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
        for (id, stamp) in demandTimestamps {
            guard registry.manifest(for: id)?.kind == .systemTransient else { continue }
            result.append(Candidate(
                id: id,
                priority: Int.max,
                requestedAt: stamp
            ))
        }
        return result.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.requestedAt < $1.requestedAt
        }
    }

    /// 后台服务发现内容变化时唤醒小组件：有内容则确保实例并 `refresh`（由其自行 requestDisplay）；
    /// 无内容仅在实例仍存活时 refresh（以便 withdraw），避免空闲时反复创建再被 reap。
    func nudgeContentWidget(_ id: WidgetID, hasContent: Bool) {
        guard registry.manifest(for: id)?.kind == .content else { return }
        guard settings.isEnabled(id) else {
            if demandTimestamps[id] != nil {
                withdrawDisplay(id)
            }
            return
        }
        if hasContent {
            let widget = ensureInstance(id)
            widget?.refresh()
        } else if let widget = instances[id] {
            widget.refresh()
        }
    }

    /// 设置页开关后：确保实例存活并 recompute。
    /// 不强制 requestDisplay——内容型小组件由自身在「有内容」时申请；无内容不得占岛分页。
    func focusForSettings(_ id: WidgetID) {
        guard registry.manifest(for: id)?.kind == .content else { return }
        guard settings.isEnabled(id) else {
            AppLog.debug("Widget", "设置聚焦跳过：未启用", ["id": id])
            return
        }
        _ = ensureInstance(id)
        if demandTimestamps[id] != nil {
            browseOverrideID = id
            rememberBrowsePage(id)
            AppLog.info("Widget", "设置聚焦：组件已有内容，切到该页", ["id": id])
        } else {
            browseOverrideID = nil
            AppLog.info("Widget", "设置聚焦：已启用但暂无内容，不上岛", ["id": id])
        }
        recompute(reason: "settingsFocus")
    }

    /// 强制切到指定内容页（番茄终局命名、媒体出曲等）。
    /// - Parameter remember: 是否写入「上次浏览页」。媒体自动抢页应传 `false`，避免覆盖用户手势记忆。
    func revealPage(_ id: WidgetID, reason: String, remember: Bool = true) {
        guard registry.manifest(for: id)?.kind == .content else { return }
        guard settings.isEnabled(id) else {
            AppLog.warn("Widget", "强制切页跳过：未启用", ["id": id, "reason": reason])
            return
        }
        _ = ensureInstance(id)
        if demandTimestamps[id] == nil {
            demandTimestamps[id] = Date()
        }
        let already = browseOverrideID == id || activeID == id
        browseOverrideID = id
        if remember {
            rememberBrowsePage(id)
        }
        recompute(reason: "reveal:\(reason)")
        AppLog.info("Widget", "强制切页", [
            "id": id,
            "reason": reason,
            "remember": remember,
            "already": already,
            "index": pageIndex,
            "pages": pageIDs.count
        ])
    }

    /// 收岛后把当前页拨回用户上次手势停留的页，供下次悬停展开。
    func restoreRememberedBrowseAfterCollapse(reason: String) {
        guard let remembered = rememberedBrowsePageID() else { return }
        if browseOverrideID == remembered, activeID == remembered { return }
        browseOverrideID = remembered
        recompute(reason: "collapseRestore:\(reason)")
        AppLog.info("Widget", "收起后恢复上次浏览页", [
            "id": remembered,
            "reason": reason,
            "active": activeID ?? "nil"
        ])
    }

    func recompute(reason: String) {
        for id in Array(demandTimestamps.keys) {
            let kind = registry.manifest(for: id)?.kind
            if kind == .systemTransient { continue }
            guard settings.isEnabled(id) else {
                demandTimestamps.removeValue(forKey: id)
                if browseOverrideID == id {
                    browseOverrideID = nil
                }
                AppLog.debug("Widget", "已禁用，撤出争夺", ["id": id, "reason": reason])
                continue
            }
        }

        for id in settings.order where settings.isEnabled(id) {
            _ = ensureInstance(id)
        }
        // 瞬时通知常驻实例，以便订阅业务事件。
        _ = ensureInstance(SystemWidgetID.islandNotice)

        var demanding = Set(
            settings.order.filter {
                settings.isEnabled($0)
                    && demandTimestamps[$0] != nil
                    && registry.manifest(for: $0)?.kind == .content
            }
        )
        for id in demandTimestamps.keys where registry.manifest(for: id)?.kind == .systemTransient {
            demanding.insert(id)
        }

        let built = buildVisiblePages(demanding: demanding)
        pages = built.map(\.ids)
        pageIDs = built.map { representative(of: $0.ids) }

        if let browse = browseOverrideID, !pageIDs.contains(browse) {
            if let idx = built.firstIndex(where: { $0.ids.contains(browse) }) {
                browseOverrideID = pageIDs[idx]
            } else {
                browseOverrideID = nil
            }
        }

        let chosenPageIndex: Int
        if let browse = browseOverrideID,
           let idx = pageIDs.firstIndex(of: browse) {
            chosenPageIndex = idx
            rememberBrowsePage(browse)
        } else if shouldRestoreRememberedPage(reason: reason),
                  let remembered = rememberedBrowsePageID(),
                  let idx = pageIDs.firstIndex(of: remembered) {
            // 冷启动 / 瞬时通知结束后：恢复用户上次停留的页。
            // 不在普通 request 路径恢复，以免挡住媒体等自动上岛。
            chosenPageIndex = idx
            browseOverrideID = remembered
            AppLog.info("Widget", "已恢复上次小组件页", [
                "id": remembered,
                "reason": reason
            ])
        } else if let top = scheduledCandidates().first,
                  let idx = built.firstIndex(where: { $0.ids.contains(top.id) }) {
            chosenPageIndex = idx
            browseOverrideID = nil
        } else {
            chosenPageIndex = 0
        }

        if built.isEmpty {
            pageIndex = 0
            applyPage([], tall: false, reason: reason)
        } else {
            let index = min(max(chosenPageIndex, 0), built.count - 1)
            pageIndex = index
            applyPage(built[index].ids, tall: built[index].isTall, reason: reason)
        }

        reapUnneeded(reason: reason)
    }

    private struct VisiblePage {
        let ids: [WidgetID]
        let isTall: Bool
    }

    /// 瞬时通知页优先；随后每个控制台模块一高页；争夺中的内容型各占一页。
    private func buildVisiblePages(demanding: Set<WidgetID>) -> [VisiblePage] {
        var result: [VisiblePage] = []
        let transientIDs = demanding
            .filter { registry.manifest(for: $0)?.kind == .systemTransient }
            .sorted { (demandTimestamps[$0] ?? .distantPast) < (demandTimestamps[$1] ?? .distantPast) }
        for id in transientIDs {
            result.append(VisiblePage(ids: [id], isTall: false))
        }
        for pane in controlDeck.enabledPanes {
            result.append(VisiblePage(ids: [pane.pageID], isTall: true))
        }
        for id in settings.order where demanding.contains(id) {
            result.append(VisiblePage(ids: [id], isTall: false))
        }
        return result
    }

    private func representative(of page: [WidgetID]) -> WidgetID {
        if page.count == 1 { return page[0] }
        return page.max(by: { settings.priority(for: $0) < settings.priority(for: $1) }) ?? page[0]
    }

    private func applyPage(_ page: [WidgetID], tall: Bool, reason: String) {
        let showingEmpty = page.isEmpty
        let deckPageID = page.count == 1 ? page[0] : nil
        let controlDeckPage = !showingEmpty
            && deckPageID.map { ControlDeckSettings.isControlDeckPageID($0) } == true
        let transientNoticePage = !showingEmpty
            && page.count == 1
            && page.first.map { registry.manifest(for: $0)?.kind == .systemTransient } == true
        isShowingEmpty = showingEmpty
        isControlDeckPage = controlDeckPage
        isTransientNoticePage = transientNoticePage
        isComboPage = tall && !showingEmpty

        let leaving: Set<WidgetID>
        if showingEmpty {
            leaving = appearedIDs.subtracting([SystemWidgetID.empty])
        } else if controlDeckPage {
            leaving = appearedIDs
        } else {
            leaving = appearedIDs.subtracting(Set(page))
        }
        for id in leaving {
            instances[id]?.onDisappear()
            AppLog.debug("Widget", "onDisappear", ["id": id, "reason": reason])
        }

        if showingEmpty {
            visibleWidgetIDs = []
            visiblePlacements = []
            _ = ensureInstance(SystemWidgetID.empty)
            if !appearedIDs.contains(SystemWidgetID.empty) {
                instances[SystemWidgetID.empty]?.onAppear()
                instances[SystemWidgetID.empty]?.refresh()
            }
            activeID = SystemWidgetID.empty
            activeTitle = ""
            appearedIDs = [SystemWidgetID.empty]
        } else if controlDeckPage, let deckPageID {
            visibleWidgetIDs = []
            visiblePlacements = []
            activeID = deckPageID
            if let pane = ControlDeckSettings.Pane.from(pageID: deckPageID) {
                activeTitle = pane.title
                controlDeck.syncActivePane(fromPageID: deckPageID)
            } else {
                activeTitle = L10n.ControlDeck.title
            }
            appearedIDs = []
        } else {
            let items = page.map { ($0, settings.gridSize(for: $0)) }
            let placements: [WidgetGridPlacement]
            if let packed = WidgetGridPacker.pack(items) {
                placements = packed
            } else {
                let primary = representative(of: page)
                AppLog.warn("Widget", "当前页超格，降级单组件", [
                    "widgets": page.count,
                    "primary": primary,
                    "reason": reason
                ])
                placements = [
                    WidgetGridPlacement(
                        id: primary,
                        column: 0,
                        row: 0,
                        size: settings.gridSize(for: primary)
                    )
                ]
            }
            visibleWidgetIDs = placements.map(\.id)
            visiblePlacements = placements
            // 先登记 appeared，再 onAppear/refresh，避免 refresh→requestDisplay→recompute 再次走进本分支。
            let newlyAppeared = visibleWidgetIDs.filter { !appearedIDs.contains($0) }
            appearedIDs = Set(visibleWidgetIDs)
            for id in visibleWidgetIDs {
                let widget = ensureInstance(id)
                widget?.priority = settings.priority(for: id)
            }
            for id in newlyAppeared {
                instances[id]?.onAppear()
                instances[id]?.refresh()
                AppLog.debug("Widget", "onAppear", ["id": id, "reason": reason])
            }
            let primary = representative(of: visibleWidgetIDs)
            activeID = primary
            activeTitle = instances[primary]?.title
                ?? registry.manifest(for: primary)?.displayName
                ?? primary
        }

        contentEpoch &+= 1
        AppLog.info("Widget", "切换当前页", [
            "primary": activeID ?? "nil",
            "reason": reason,
            "empty": showingEmpty,
            "controlDeck": controlDeckPage,
            "notice": transientNoticePage,
            "tall": tall,
            "widgets": visibleWidgetIDs.count,
            "pageIndex": pageIndex,
            "pages": pages.count
        ])
    }

    @discardableResult
    private func ensureInstance(_ id: WidgetID) -> (any IslandWidget)? {
        if let existing = instances[id] { return existing }
        if creatingIDs.contains(id) {
            AppLog.warn("Widget", "创建重入，跳过重复实例", ["id": id])
            return nil
        }
        creatingIDs.insert(id)
        defer { creatingIDs.remove(id) }

        let context = WidgetContextImpl(widgetID: id, runtime: self)
        guard let widget = registry.make(id: id, context: context) else { return nil }
        widget.priority = settings.priority(for: id)
        instances[id] = widget
        if widget.wantsDisplay, demandTimestamps[id] == nil {
            demandTimestamps[id] = widget.requestedAt
            AppLog.debug("Widget", "创建时即争夺展示", ["id": id])
        }
        return widget
    }

    private func reapUnneeded(reason: String) {
        var keep = Set(settings.pinnedIDs.filter { settings.isEnabled($0) })
        keep.formUnion(visibleWidgetIDs)
        keep.insert(SystemWidgetID.empty)
        keep.insert(SystemWidgetID.islandNotice)
        keep.formUnion(demandTimestamps.keys.filter {
            registry.manifest(for: $0)?.kind == .systemTransient || settings.isEnabled($0)
        })
        for id in Array(instances.keys) where !keep.contains(id) {
            tearDown(id, reason: reason)
        }
    }

    private func tearDown(_ id: WidgetID, reason: String) {
        guard id != SystemWidgetID.empty || reason == "stop" else { return }
        guard let widget = instances.removeValue(forKey: id) else { return }
        if appearedIDs.contains(id) {
            widget.onDisappear()
            appearedIDs.remove(id)
        }
        if activeID == id {
            activeID = nil
            activeTitle = ""
            isShowingEmpty = true
        }
        AppLog.debug("Widget", "销毁实例", ["id": id, "reason": reason])
    }
}
