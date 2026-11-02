import AppKit
import Combine
import SwiftUI

/// 灵动岛窗口控制器：几何对齐、悬停展开、全屏隐藏、多屏降级。
@MainActor
final class IslandController: NSObject {
    /// 设置页实时预览用；由 `start()` 挂上。
    private(set) static weak var shared: IslandController?

    let viewModel = IslandViewModel()
    private let settings = IslandSettings.shared
    private let window = IslandWindow.make()
    private let hitTestView = IslandHitTestView()
    private var hostingView: IslandHostingView<IslandContentView>?
    private var geometry: NotchGeometry?
    private var targetScreen: NSScreen?

    private let fullscreenMonitor = FullscreenMonitor()
    private let displayMonitor = DisplayMonitor()
    private var appearanceObserver: AnyCancellable?
    private var settingsObservers: Set<AnyCancellable> = []

    /// 用屏幕坐标轮询指针，避免 trackingArea 随窗口变形导致抖动。
    private var hoverTimer: Timer?
    /// 指针是否在岛热区内（瞬时通知据此暂停 2s 自动收起）。
    private(set) var isPointerOverIsland = false
    /// 对外别名，供 `IslandNoticeWidget` 等读取悬停态。
    var isHoveringIsland: Bool { isPointerOverIsland }
    private var collapseWorkItem: DispatchWorkItem?
    /// 岛内按下拖拽中：保持接收事件，避免穿透把翻页掐断。
    private var isMouseDownInIsland = false
    /// 系统拖文件进入岛 / 悬停在货架投放区：钉住展开，避免展开收起来回闪。
    private var isShelfFileDragPinned = false
    /// SwiftUI 货架 `.onDrop(isTargeted:)` 命中中。
    private var isShelfDropTargeted = false
    /// 拖文件接近货架时临时抬高层级，便于抢到投放命中。
    private var isShelfDragElevated = false
    /// 整岛暂存拖入会话是否仍有效（接近区或投放命中）。
    var isShelfDragSessionActive: Bool {
        isShelfFileDragPinned || isShelfDropTargeted
    }
    private lazy var islandRestingLevel = window.level
    private var pagePanRecognizer: NSPanGestureRecognizer?
    /// 触控板横滑：nonactivating Panel 上的 scrollWheel 常被系统送给下层 App，用监视器兜底。
    private var scrollLocalMonitor: Any?
    private var scrollGlobalMonitor: Any?
    private var scrollAccumX: CGFloat = 0
    private var lastPageSwipeAt: Date = .distantPast
    /// 从控制台翻到矮页后，短暂沿用控制台热区，避免指针还在原下半截被当成离开。
    private var hoverLayoutBoostUntil: Date = .distantPast
    private var hoverLayoutBoost: NotchGeometry.ExpandedLayout?
    /// 设置窗仍打开（不论是否在前台）。
    private var isSettingsSessionActive = false
    /// 设置窗在前台有焦点时钉住展开；失焦后关掉，岛恢复悬停正常逻辑。
    private var isSettingsLivePreview = false
    /// 灵动岛设置页要实时预览；小组件 / 控制台设计页保持收起。
    private var settingsPreferLivePreview = true

    func start() {
        Self.shared = self
        WidgetRuntime.shared.start()
        installContent()

        displayMonitor.onScreensChanged = { [weak self] in
            self?.relayout(reason: "screenParams")
        }
        displayMonitor.start()

        fullscreenMonitor.onChange = { [weak self] fullscreen in
            self?.applyFullscreen(fullscreen)
        }
        fullscreenMonitor.start()

        appearanceObserver = viewModel.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.handleAppearanceChange(appearance)
            }

        settings.$hideInFullscreen
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                AppLog.info("Settings", "全屏禁用岛设置变更，立即重算", ["enabled": enabled])
                self?.fullscreenMonitor.refresh(reason: "setting")
                self?.applyFullscreen(self?.fullscreenMonitor.isFullscreenActive ?? false)
            }
            .store(in: &settingsObservers)

        settings.$expandedWidth
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] width in
                guard let self else { return }
                // 窗体占位固定最大宽，这里主要刷新可点区与日志。
                AppLog.info("Settings", "展开宽度变更", [
                    "width": width,
                    "expanded": self.viewModel.isExpanded
                ])
                self.applyWindowFrame(animated: false)
            }
            .store(in: &settingsObservers)

        WidgetRuntime.shared.$isComboPage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] combo in
                AppLog.info("Island", "高页布局切换", ["tall": combo])
                self?.updateInteractiveFrame()
            }
            .store(in: &settingsObservers)

        WidgetRuntime.shared.$isControlDeckPage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] deck in
                AppLog.info("Island", "控制台页尺寸切换", [
                    "controlDeck": deck,
                    "preferredW": NotchGeometry.controlDeckPreferredWidth,
                    "minH": NotchGeometry.controlDeckMinHeight
                ])
                self?.updatePagePanEnabled()
                self?.applyWindowFrame(animated: false)
            }
            .store(in: &settingsObservers)

        WidgetRuntime.shared.$isTransientNoticePage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] notice in
                AppLog.info("Island", "瞬时通知页尺寸切换", ["notice": notice])
                self?.updatePagePanEnabled()
                self?.updateInteractiveFrame()
                self?.applyWindowFrame(animated: false)
            }
            .store(in: &settingsObservers)

        WidgetRuntime.shared.$pageIDs
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.updatePagePanEnabled()
            }
            .store(in: &settingsObservers)

        startHoverPolling()
        relayout(reason: "start")
        AppLog.info("Island", "控制器已启动")
    }

    func stop() {
        stopHoverPolling()
        stopScrollPagingMonitors()
        collapseWorkItem?.cancel()
        isSettingsLivePreview = false
        isSettingsSessionActive = false
        settingsPreferLivePreview = true
        fullscreenMonitor.stop()
        displayMonitor.stop()
        appearanceObserver?.cancel()
        settingsObservers.removeAll()
        WidgetRuntime.shared.stop()
        window.orderOut(nil)
        if Self.shared === self {
            Self.shared = nil
        }
    }

    /// 设置窗打开且在前台：钉住展开（灵动岛设置页用）。
    func beginSettingsSession() {
        isSettingsSessionActive = true
        settingsPreferLivePreview = true
        setSettingsLivePreview(true)
        AppLog.info("Island", "设置会话：钉住展开预览")
    }

    /// 设置窗打开但保持收起（小组件 / 控制台设计页：页内自有预览，不再展开真岛）。
    func beginSettingsSessionCollapsed() {
        isSettingsSessionActive = true
        settingsPreferLivePreview = false
        isSettingsLivePreview = false
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if viewModel.isExpanded {
            viewModel.collapse()
            applyWindowFrame(animated: true)
            updateInteractiveFrame()
        }
        AppLog.info("Island", "设置会话：保持收起", ["expanded": false])
    }

    /// 设置窗仍打开，但焦点离开（切到其它 App / 其它窗）：恢复岛的正常悬停逻辑。
    /// 焦点回到设置窗：若当前页需要预览则再次钉住展开。
    func setSettingsWindowFocused(_ focused: Bool) {
        guard isSettingsSessionActive else {
            AppLog.debug("Island", "忽略设置焦点变更（无会话）", [
                "focused": focused,
                "key": Self.describeKeyWindow()
            ])
            return
        }
        if focused {
            AppLog.info("Island", "设置窗重新聚焦", [
                "appActive": NSApp.isActive,
                "key": Self.describeKeyWindow(),
                "preferPreview": settingsPreferLivePreview,
                "preview": isSettingsLivePreview
            ])
            if settingsPreferLivePreview {
                setSettingsLivePreview(true)
            }
        } else {
            AppLog.info("Island", "设置窗失焦，岛恢复正常悬停", [
                "appActive": NSApp.isActive,
                "key": Self.describeKeyWindow(),
                "pointerOver": isPointerOverIsland,
                "preview": isSettingsLivePreview
            ])
            // 关掉钉住，不强制收起：指针在岛上则保持，否则走正常收起。
            setSettingsLivePreview(false, forceCollapseOnEnd: false)
        }
    }

    /// 设置页打开某个小组件开关：切到该页；仅在「灵动岛」设置预览模式下展开真岛。
    func presentWidgetEnabled(_ id: WidgetID, fromScreenRect: CGRect?) {
        WidgetRuntime.shared.focusForSettings(id)
        guard settingsPreferLivePreview else {
            AppLog.info("Island", "开关开启：设计页保持收起", ["id": id])
            return
        }
        setSettingsLivePreview(true)
        expand(reason: "widgetEnable")
        applyWindowFrame(animated: true)
        updateInteractiveFrame()

        guard let fromScreenRect,
              fromScreenRect.width > 8,
              fromScreenRect.height > 8,
              let geometry
        else {
            AppLog.info("Island", "开关开启：无飞入起点，直接展示", ["id": id])
            return
        }

        let dest = geometry.expandedFrameOnScreen(width: CGFloat(settings.expandedWidth))
        WidgetFlyAnimator.shared.play(widgetID: id, from: fromScreenRect, to: dest) {
            AppLog.info("Island", "开关开启飞入完成", ["id": id])
        }
    }

    /// 设置页拖拽排序落点后：切到该页；设计页不展开真岛。
    func presentWidgetReordered(_ id: WidgetID) {
        WidgetRuntime.shared.focusForSettings(id)
        guard settingsPreferLivePreview else {
            AppLog.info("Island", "排序后：设计页保持收起", ["id": id])
            return
        }
        setSettingsLivePreview(true)
        if !viewModel.isExpanded {
            expand(reason: "widgetReorder")
            applyWindowFrame(animated: true)
            updateInteractiveFrame()
        }
        AppLog.info("Island", "排序后展示小组件", ["id": id])
    }

    /// 钉住 / 取消钉住展开。
    /// - Parameter forceCollapseOnEnd: 关设置窗时传 `true`，强制收起。
    func setSettingsLivePreview(_ enabled: Bool, forceCollapseOnEnd: Bool = false) {
        if enabled {
            isSettingsSessionActive = true
            if isSettingsLivePreview {
                if !viewModel.isExpanded {
                    expand(reason: "settingsPreview")
                }
                return
            }
            isSettingsLivePreview = true
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            AppLog.info("Island", "设置页实时预览：钉住展开", ["expanded": true])
            expand(reason: "settingsPreview")
            updateInteractiveFrame()
            return
        }

        let wasPreview = isSettingsLivePreview
        isSettingsLivePreview = false
        if forceCollapseOnEnd {
            isSettingsSessionActive = false
        }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        AppLog.info("Island", "设置页实时预览结束", [
            "wasPreview": wasPreview,
            "pointerOver": isPointerOverIsland,
            "forceCollapse": forceCollapseOnEnd,
            "sessionActive": isSettingsSessionActive
        ])
        if forceCollapseOnEnd || (!isPointerOverIsland && !isMouseDownInIsland) {
            collapse(reason: "settingsPreviewEnd")
        }
    }

    func expand(reason: String) {
        guard !viewModel.isExpanded else { return }
        AppLog.info("Island", "展开灵动岛", [
            "reason": reason,
            "expanded": true,
            "settingsSession": isSettingsSessionActive,
            "settingsPreview": isSettingsLivePreview,
            "prevKey": Self.describeKeyWindow()
        ])
        viewModel.expand()
        // 不依赖 Combine 时序：展开后立刻把可点区扩到面板，否则仍是刘海 171×30，控制台点全落空。
        updateInteractiveFrame(expanded: true)
        ensureIslandInteractionReady(reason: "expand:\(reason)")
        startScrollPagingMonitors()
    }

    func collapse(reason: String) {
        guard viewModel.isExpanded else { return }
        if isSettingsLivePreview, reason != "settingsPreviewEnd" {
            AppLog.debug("Island", "设置预览中，忽略收起", ["reason": reason])
            return
        }
        // 仅投放区仍命中时挡收起；指针已离开则允许 hoverEnd 收起。
        if isShelfDropTargeted, reason == "hoverEnd" {
            AppLog.debug("Island", "货架投放区命中中，忽略收起", ["targeted": true])
            return
        }
        AppLog.info("Island", "收起灵动岛", [
            "reason": reason,
            "expanded": false,
            "wasKey": window.isKeyWindow,
            "key": Self.describeKeyWindow()
        ])
        viewModel.collapse()
        updateInteractiveFrame(expanded: false)
        stopScrollPagingMonitors()
        scrollAccumX = 0
        if window.isKeyWindow {
            window.resignKey()
            AppLog.debug("Island", "收起后 resignKey", ["key": Self.describeKeyWindow()])
        }
        demoteIslandInteractionIfNeeded(reason: "collapse:\(reason)")
    }

    private static func describeKeyWindow() -> String {
        guard let key = NSApp.keyWindow else { return "nil" }
        let title = key.title.isEmpty ? String(describing: type(of: key)) : key.title
        return "\(title)#\(ObjectIdentifier(key))"
    }

    // MARK: - Hover (screen-space)

    private func startHoverPolling() {
        stopHoverPolling()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPointer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func pollPointer() {
        guard viewModel.isVisibleOnDisplay, !viewModel.isHiddenForFullscreen else {
            // 隐藏时仍可能占着展开窗框，必须穿透，否则挡下方点击。
            setClickThrough(true, reason: "hidden")
            return
        }
        guard let geometry else {
            setClickThrough(true, reason: "noGeometry")
            return
        }

        let mouse = NSEvent.mouseLocation

        // 设置窗与展开岛常在屏幕上方重叠；命中设置窗时必须穿透，否则输入框失焦后点击会被岛吞掉。
        if isSettingsSessionActive,
           let settingsWindow = MenuBarController.shared?.settingsWindow,
           settingsWindow.frame.contains(mouse) {
            setClickThrough(true, reason: "pointerOverSettings")
            let leftIsland = isPointerOverIsland || viewModel.isExpanded
            isPointerOverIsland = false
            if isSettingsLivePreview {
                // 灵动岛设置页：钉住展开，指针回设置窗也不收。
                if !viewModel.isExpanded {
                    expand(reason: "settingsPreview")
                }
            } else if leftIsland, !isMouseDownInIsland {
                // 控制台 / 小组件设计页：设置窗与展开岛几何重叠，
                // 延迟收起的 stillOver 复查会误判「还在岛上」→ 必须立刻收起。
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
                collapse(reason: "pointerOverSettings")
            }
            return
        }

        let over = pointerIsOverIsland(
            mouse: mouse,
            geometry: geometry,
            expanded: viewModel.isExpanded
        )
        let fileDrag = Self.isFileDragInProgress()
        let shelfEnabled = ControlDeckSettings.shared.isModuleEnabled("shelf")
        // 用「控制台展开框」作磁吸区：拖文件靠近时提前展开，不必顶到屏幕最上沿
        // （顶边会触发系统调度中心 / 空间切换，优先级高于第三方窗）。
        let approach = shelfEnabled && fileDrag
            && pointerIsInShelfDropApproachZone(mouse: mouse, geometry: geometry)

        // 仅在「接近 / 在岛上 / 投放区命中」且拖文件进行中时钉住；驶出即解除。
        let wantShelfHold = shelfEnabled
            && (over || isShelfDropTargeted || approach)
            && (fileDrag || isShelfDropTargeted)
        if isShelfFileDragPinned != wantShelfHold {
            isShelfFileDragPinned = wantShelfHold
            if wantShelfHold {
                ControlDeckSettings.shared.focusShelfForDrop()
                AppLog.info("Island", "货架拖入：钉住展开", [
                    "over": over,
                    "targeted": isShelfDropTargeted,
                    "approach": approach
                ])
            } else {
                AppLog.info("Island", "货架拖入：解除钉住", [
                    "over": over,
                    "targeted": isShelfDropTargeted,
                    "fileDrag": fileDrag,
                    "approach": approach
                ])
            }
        }
        // 接近 / 命中岛时整岛切到暂存区；离开拖拽后恢复原页。
        ShelfDropSession.shared.setActive(
            wantShelfHold,
            reason: wantShelfHold
                ? (isShelfDropTargeted ? "dropTargeted" : (approach ? "approach" : "over"))
                : "dragEnded"
        )
        setShelfDragWindowElevation(wantShelfHold)

        // 窗体始终按展开尺寸占位；收起时刘海以外必须穿透。
        // 货架接近 / 投放命中时不穿透，否则收不到 onDrop。
        let shelfHold = isShelfFileDragPinned || isShelfDropTargeted
        let shouldIgnore = !over && !isMouseDownInIsland && !shelfHold
        setClickThrough(
            shouldIgnore,
            reason: shelfHold ? "shelfDropHold" : (over ? "pointerOver" : (isMouseDownInIsland ? "dragHold" : "pointerAway"))
        )

        if isSettingsLivePreview {
            isPointerOverIsland = over
            if !viewModel.isExpanded {
                expand(reason: "settingsPreview")
            }
            return
        }

        // 拖文件进入磁吸区 / 投放区：提前展开，松手点落在面板中部，躲开顶边调度中心。
        if shelfHold {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if !viewModel.isExpanded {
                expand(reason: approach && !over ? "shelfDropApproach" : "shelfDrop")
            }
            isPointerOverIsland = over || isShelfDropTargeted || approach
            return
        }

        if over == isPointerOverIsland { return }
        isPointerOverIsland = over

        if over {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            expand(reason: "hover")
        } else if !isMouseDownInIsland {
            scheduleCollapse()
        }
    }

    /// 货架 SwiftUI drop 命中变化：命中期间同样钉住展开。
    func setShelfDropTargeted(_ targeted: Bool) {
        guard isShelfDropTargeted != targeted else { return }
        isShelfDropTargeted = targeted
        AppLog.info("Island", "货架投放区命中", ["targeted": targeted])
        if targeted {
            isShelfFileDragPinned = true
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            ControlDeckSettings.shared.focusShelfForDrop()
            ShelfDropSession.shared.setActive(true, reason: "dropTargeted")
            if !viewModel.isExpanded {
                expand(reason: "shelfDropTargeted")
            }
            setClickThrough(false, reason: "shelfDropTargeted")
        } else if !isShelfFileDragPinned {
            ShelfDropSession.shared.setActive(false, reason: "dropUntargeted")
        }
    }

    /// 正在拖文件：须同时满足左键按下 + 拖放剪贴板带 fileURL。
    /// 仅查 pasteboard 不够——松手后类型常残留，会把货架钉住展开卡死。
    private static func isFileDragInProgress() -> Bool {
        guard NSEvent.pressedMouseButtons & (1 << 0) != 0 else { return false }
        let drag = NSPasteboard(name: .drag)
        guard let types = drag.types, !types.isEmpty else { return false }
        return types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("public.file-url"))
    }

    /// 拖文件磁吸区：控制台展开框再向下 / 左右扩一圈。
    /// 指针进入此区即展开货架，避免为命中刘海而顶到屏幕最上沿触发调度中心。
    private func pointerIsInShelfDropApproachZone(mouse: NSPoint, geometry: NotchGeometry) -> Bool {
        let width = CGFloat(IslandSettings.shared.expandedWidth)
        var zone = geometry.expandedFrameOnScreen(width: width, layout: .controlDeck)
        // 下扩：从面板下方就能吸住；左右略扩方便斜着拖入。
        zone = zone.insetBy(dx: -36, dy: 0)
        zone.origin.y -= 72
        zone.size.height += 72
        return zone.contains(mouse)
    }

    private func setShelfDragWindowElevation(_ elevated: Bool) {
        guard isShelfDragElevated != elevated else { return }
        isShelfDragElevated = elevated
        if elevated {
            // 抬到弹出菜单级，仍低于系统拖影；提高相对其它浮层的投放命中机会。
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            window.orderFrontRegardless()
            AppLog.debug("Island", "货架拖入：抬高窗口层级")
        } else {
            window.level = islandRestingLevel
            AppLog.debug("Island", "货架拖入：恢复窗口层级")
        }
    }

    /// `true` = 整窗点击穿透到下层 App；悬停进入可交互区后再关闭穿透。
    private func setClickThrough(_ enabled: Bool, reason: String) {
        guard window.ignoresMouseEvents != enabled else { return }
        window.ignoresMouseEvents = enabled
        if !enabled, viewModel.isExpanded {
            ensureIslandInteractionReady(reason: "clickThroughOff:\(reason)")
        }
        let level: (String, [String: Any]) -> Void = { message, fields in
            if WidgetRuntime.shared.isControlDeckPage {
                AppLog.info("Overlay", message, fields)
            } else {
                AppLog.debug("Overlay", message, fields)
            }
        }
        level(enabled ? "开启点击穿透" : "关闭点击穿透", [
            "reason": reason,
            "expanded": viewModel.isExpanded,
            "controlDeck": WidgetRuntime.shared.isControlDeckPage,
            "islandKey": window.isKeyWindow,
            "appActive": NSApp.isActive
        ])
    }

    /// 对齐「开设置就能点」的条件：临时升到 regular + activate + makeKey。
    /// 纯 accessory 下 `NSApp.activate` 常常不生效（日志里 activated=true 但 appActive 仍 false）。
    private func ensureIslandInteractionReady(reason: String) {
        if isSettingsSessionActive {
            AppLog.debug("Overlay", "设置会话中跳过岛激活", [
                "reason": reason,
                "appActive": NSApp.isActive,
                "key": Self.describeKeyWindow()
            ])
            return
        }

        var promoted = false
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            promoted = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        AppLog.info("Overlay", "岛交互就绪", [
            "reason": reason,
            "promoted": promoted,
            "appActive": NSApp.isActive,
            "islandKey": window.isKeyWindow,
            "policy": NSApp.activationPolicy() == .regular ? "regular" : "accessory"
        ])
    }

    /// 收起后若设置窗未开，降回 accessory，避免常驻 Dock。
    private func demoteIslandInteractionIfNeeded(reason: String) {
        if isSettingsSessionActive { return }
        if MenuBarController.shared?.settingsWindow != nil { return }
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("Overlay", "岛收起后降回 accessory", [
            "reason": reason,
            "appActive": NSApp.isActive
        ])
    }

    /// 刘海本体始终算「在岛上」；展开后按「当前页实际面积」判断（见 `hoverRetentionLayout`）。
    private func pointerIsOverIsland(
        mouse: NSPoint,
        geometry: NotchGeometry,
        expanded: Bool
    ) -> Bool {
        // 略放大刘海热区，更容易指到。
        let notchHit = geometry.notchFrame.insetBy(dx: -4, dy: -2)
        if notchHit.contains(mouse) {
            return true
        }
        if expanded {
            let layout = hoverRetentionLayout(for: WidgetRuntime.shared)
            let width = CGFloat(IslandSettings.shared.expandedWidth)
            let body = geometry.expandedFrameOnScreen(width: width, layout: layout)
                .insetBy(dx: -2, dy: -2)
            if body.contains(mouse) {
                return true
            }
        }
        return false
    }

    /// 悬停保留区跟当前页走：小组件用矮区，控制台用高区。
    /// 仅在刚从控制台翻走的短窗口内临时抬到控制台高度，避免翻页误收。
    private func hoverRetentionLayout(for runtime: WidgetRuntime) -> NotchGeometry.ExpandedLayout {
        if let boost = hoverLayoutBoost, Date() < hoverLayoutBoostUntil {
            return boost
        }
        if hoverLayoutBoost != nil {
            hoverLayoutBoost = nil
        }
        if runtime.isControlDeckPage { return .controlDeck }
        if runtime.isTransientNoticePage { return .notice }
        if runtime.isComboPage { return .combo }
        return .standard
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        // 刚翻页时高度会变，给指针一点时间落在新面板上，避免误收。
        let delay: TimeInterval = Date().timeIntervalSince(lastPageSwipeAt) < 0.45 ? 0.36 : 0.12
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 收起前再确认一次，避免边缘抖动。
            guard let geometry else {
                self.collapse(reason: "hoverEnd")
                return
            }
            let mouse = NSEvent.mouseLocation
            // 设置窗盖住岛展开区时，不算「还在岛上」（否则设计页永远收不起来）。
            if self.isPointerOverSettingsWindow(mouse), !self.isSettingsLivePreview {
                self.isPointerOverIsland = false
                self.collapse(reason: "hoverEnd")
                return
            }
            let stillOver = self.pointerIsOverIsland(
                mouse: mouse,
                geometry: geometry,
                expanded: true
            )
            if stillOver {
                self.isPointerOverIsland = true
                return
            }
            self.collapse(reason: "hoverEnd")
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func isPointerOverSettingsWindow(_ mouse: NSPoint) -> Bool {
        guard isSettingsSessionActive,
              let settingsWindow = MenuBarController.shared?.settingsWindow
        else { return false }
        return settingsWindow.frame.contains(mouse)
    }

    private static func expandedLayout(for runtime: WidgetRuntime) -> NotchGeometry.ExpandedLayout {
        if runtime.isControlDeckPage { return .controlDeck }
        if runtime.isTransientNoticePage { return .notice }
        if runtime.isComboPage { return .combo }
        return .standard
    }

    // MARK: - Layout

    private func installContent() {
        let root = IslandContentView(
            viewModel: viewModel,
            settings: settings,
            runtime: WidgetRuntime.shared
        )
        let hosting = IslandHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.onHorizontalPageSwipe = { [weak self] offset in
            self?.commitPageSwipe(offset: offset, source: "hostingScroll")
        }
        hostingView = hosting

        hitTestView.wantsLayer = true
        hitTestView.layer?.backgroundColor = NSColor.clear.cgColor
        hitTestView.addSubview(hosting)

        // SwiftUI DragGesture 在 nonactivating Panel 上不可靠；用 AppKit 平移识别拖拽翻页。
        // 不可 delaysPrimaryMouseButtonEvents：否则会吞掉混音台按钮的 mouseDown。
        let pan = HorizontalPagePanRecognizer(target: self, action: #selector(handlePagePan(_:)))
        pan.delaysPrimaryMouseButtonEvents = false
        hitTestView.addGestureRecognizer(pan)
        pagePanRecognizer = pan
        updatePagePanEnabled()

        window.contentView = hitTestView
        // 主题框层偶发带灰底，清掉后纯黑 fill 才贴得上刘海。
        if let frameView = hitTestView.superview {
            frameView.wantsLayer = true
            frameView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        AppLog.info("Island", "已安装岛内容与 device 纯黑底", [
            "theme": settings.theme.rawValue,
            "appearance": "darkAqua",
            "fill": "deviceRGB"
        ])
    }

    /// 多页时可横滑翻页（含多个控制台模块页）；单页 / 瞬时通知页关掉，避免抢按钮或滑走提示。
    private func updatePagePanEnabled() {
        let runtime = WidgetRuntime.shared
        let multi = runtime.pageIDs.count > 1 && !runtime.isTransientNoticePage
        pagePanRecognizer?.isEnabled = multi
        if runtime.isTransientNoticePage {
            AppLog.debug("Overlay", "瞬时通知页已禁用翻页手势")
        }
    }

    // MARK: - 分页手势（触控板 / 拖拽）

    private func startScrollPagingMonitors() {
        stopScrollPagingMonitors()
        scrollAccumX = 0

        scrollLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            if self.handleScrollPaging(event) {
                // 吃掉横滑，避免再派给下层或重复进 hosting。
                return nil
            }
            return event
        }

        // 前台是别的 App 时，滚轮常不进本进程；全局监视仍能看到（无需改事件）。
        scrollGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollPaging(event)
        }
        AppLog.debug("Overlay", "已启动触控板横滑监视", ["expanded": true])
    }

    private func stopScrollPagingMonitors() {
        if let scrollLocalMonitor {
            NSEvent.removeMonitor(scrollLocalMonitor)
            self.scrollLocalMonitor = nil
        }
        if let scrollGlobalMonitor {
            NSEvent.removeMonitor(scrollGlobalMonitor)
            self.scrollGlobalMonitor = nil
        }
    }

    /// 处理触控板 / 鼠标滚轮横滑。返回 `true` 表示已作为翻页消费。
    @discardableResult
    private func handleScrollPaging(_ event: NSEvent) -> Bool {
        guard viewModel.isExpanded else { return false }
        // 瞬时通知不是正规分页内容，禁止横滑切走。
        if WidgetRuntime.shared.isTransientNoticePage {
            scrollAccumX = 0
            return false
        }
        // 控制台页（货架 / 混音台）需要纵向滚动，不拦截任何滚轮。
        if WidgetRuntime.shared.isControlDeckPage {
            return false
        }
        guard let geometry else { return false }
        guard pointerIsOverIsland(
            mouse: NSEvent.mouseLocation,
            geometry: geometry,
            expanded: true
        ) else {
            scrollAccumX = 0
            return false
        }

        // 忽略惯性阶段，避免一次轻扫翻多页。
        if event.momentumPhase != [] && event.momentumPhase != .began {
            scrollAccumX = 0
            return false
        }

        let dx: CGFloat
        let dy: CGFloat
        if event.hasPreciseScrollingDeltas {
            dx = event.scrollingDeltaX
            dy = event.scrollingDeltaY
        } else {
            dx = event.deltaX
            dy = event.deltaY
        }

        guard abs(dx) > abs(dy), abs(dx) > 0.05 else {
            if event.phase == .ended || event.phase == .cancelled {
                scrollAccumX = 0
            }
            return false
        }

        scrollAccumX += dx
        AppLog.debug("Overlay", "触控板横滑累加", [
            "dx": dx,
            "accum": scrollAccumX,
            "phase": event.phase.rawValue
        ])

        if scrollAccumX <= -10 {
            commitPageSwipe(offset: 1, source: "trackpad")
            scrollAccumX = 0
            return true
        }
        if scrollAccumX >= 10 {
            commitPageSwipe(offset: -1, source: "trackpad")
            scrollAccumX = 0
            return true
        }

        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumX = 0
        }
        return true
    }

    private func commitPageSwipe(offset: Int, source: String) {
        guard viewModel.isExpanded else { return }
        if WidgetRuntime.shared.isTransientNoticePage {
            AppLog.debug("Overlay", "瞬时通知页禁止翻页", ["source": source])
            return
        }
        // 防抖：local + hosting / global 可能短时间重复触发。
        let now = Date()
        guard now.timeIntervalSince(lastPageSwipeAt) > 0.28 else {
            AppLog.debug("Overlay", "翻页防抖忽略", ["source": source, "offset": offset])
            return
        }
        lastPageSwipeAt = now
        let pages = WidgetRuntime.shared.pageIDs.count
        AppLog.info("Overlay", "翻页手势", [
            "source": source,
            "offset": offset,
            "pages": pages
        ])
        guard pages >= 2 else {
            AppLog.warn("Overlay", "可切换页不足，无法翻页", ["pages": pages])
            return
        }
        let wasControlDeck = WidgetRuntime.shared.isControlDeckPage
        // 翻页瞬间高度会变，先取消待收起，避免「还在下半截」被当成离开。
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        isPointerOverIsland = true
        WidgetRuntime.shared.selectPage(offset: offset)
        let nowControlDeck = WidgetRuntime.shared.isControlDeckPage
        if wasControlDeck, !nowControlDeck {
            hoverLayoutBoost = .controlDeck
            hoverLayoutBoostUntil = Date().addingTimeInterval(0.55)
            AppLog.debug("Island", "翻离控制台，短暂保留大热区", ["seconds": 0.55])
        } else {
            hoverLayoutBoost = nil
        }
        updateInteractiveFrame(expanded: true)
        AppLog.debug("Island", "翻页后悬停热区", [
            "hoverLayout": "\(hoverRetentionLayout(for: WidgetRuntime.shared))",
            "page": WidgetRuntime.shared.activeID ?? "nil",
            "boost": hoverLayoutBoost != nil
        ])
    }

    @objc private func handlePagePan(_ gr: NSPanGestureRecognizer) {
        switch gr.state {
        case .began:
            // 仅在确认为横向拖拽后才钉住不穿透；纯点击不会进 began（见 HorizontalPagePanRecognizer）。
            isMouseDownInIsland = true
            setClickThrough(false, reason: "panBegan")
            AppLog.debug("Overlay", "横向拖拽翻页开始")
        case .ended, .cancelled, .failed:
            defer {
                isMouseDownInIsland = false
                gr.setTranslation(.zero, in: hitTestView)
            }
            guard viewModel.isExpanded, gr.state == .ended else { return }
            let dx = gr.translation(in: hitTestView).x
            if dx <= -28 {
                AppLog.debug("Overlay", "鼠标拖拽翻页", ["offset": 1, "dx": dx])
                commitPageSwipe(offset: 1, source: "pan")
            } else if dx >= 28 {
                AppLog.debug("Overlay", "鼠标拖拽翻页", ["offset": -1, "dx": dx])
                commitPageSwipe(offset: -1, source: "pan")
            }
        default:
            break
        }
    }

    private func relayout(reason: String) {
        guard let preferred = NotchGeometryResolver.preferred() else {
            geometry = nil
            targetScreen = nil
            viewModel.isVisibleOnDisplay = false
            window.orderOut(nil)
            AppLog.warn("Island", "无刘海屏，岛窗口已隐藏（可走菜单栏）", ["reason": reason])
            return
        }

        targetScreen = preferred.0
        geometry = preferred.1
        viewModel.notchHeight = preferred.1.notchHeight
        viewModel.notchWidth = preferred.1.notchWidth
        viewModel.isVisibleOnDisplay = true
        let requestedW = CGFloat(settings.expandedWidth)
        let expanded = preferred.1.expandedSize(width: requestedW)
        viewModel.maxExpandedWidth = preferred.1.maxExpandedWidth
        AppLog.info("Notch", "对齐刘海", [
            "reason": reason,
            "display": Int(preferred.1.screenID),
            "notchW": preferred.1.notchWidth,
            "notchH": preferred.1.notchHeight,
            "panelW": expanded.width,
            "panelH": expanded.height,
            "windowW": preferred.1.windowSize.width,
            "requestedW": requestedW,
            "clamped": abs(requestedW - expanded.width) > 0.5
        ])
        if abs(requestedW - expanded.width) > 0.5 {
            AppLog.warn("Island", "展开宽度已按屏幕/刘海钳制", [
                "requested": requestedW,
                "maxW": preferred.1.maxExpandedWidth,
                "minW": preferred.1.notchWidth,
                "usedW": expanded.width
            ])
        }
        // 窗口固定最大宽占位；面板在窗内居中变宽，避免裁圆角。
        applyWindowFrame(animated: false)
        updateVisibility()
    }

    private func handleAppearanceChange(_ appearance: IslandAppearance) {
        AppLog.info("Island", appearance == .expanded ? "切换到展开态" : "切换到常驻态", [
            "expanded": appearance == .expanded
        ])
        // 以 sink 收到的 appearance 为准，避免与 viewModel 时序错位时热区停在刘海尺寸。
        updateInteractiveFrame(expanded: appearance == .expanded)
        IslandHaptics.play(settings.hapticIntensity)
    }

    private func applyWindowFrame(animated: Bool) {
        guard let geometry else { return }
        _ = animated // 窗体尺寸不跟宽度做 AppKit 动画，避免与 SwiftUI 面板抢裁切。
        viewModel.maxExpandedWidth = geometry.maxExpandedWidth
        let requestedW = CGFloat(settings.expandedWidth)
        let layout = Self.expandedLayout(for: WidgetRuntime.shared)
        let panel = geometry.expandedSize(width: requestedW, layout: layout)
        if abs(requestedW - panel.width) > 0.5, layout != .controlDeck {
            AppLog.warn("Island", "展开宽度已按屏幕/刘海钳制", [
                "requested": requestedW,
                "usedW": panel.width
            ])
        }
        // 窗口始终按控制台最大占位；面板随当前页布局变化。
        let frame = geometry.windowFrameOnScreen()
        window.setFrame(frame, display: true)
        hostingView?.frame = hitTestView.bounds
        updateInteractiveFrame()
        AppLog.debug("Island", "窗口占位已更新", [
            "windowW": frame.width,
            "windowH": frame.height,
            "panelW": panel.width,
            "panelH": panel.height,
            "layout": "\(layout)",
            "requestedW": requestedW
        ])

        if viewModel.isVisibleOnDisplay && !viewModel.isHiddenForFullscreen {
            window.orderFrontRegardless()
        }
    }

    private func updateInteractiveFrame(expanded: Bool? = nil) {
        guard let geometry else { return }
        let windowFrame = window.frame
        let isExpanded = expanded ?? viewModel.isExpanded
        let panel: CGSize
        if isExpanded {
            panel = geometry.expandedSize(
                width: CGFloat(settings.expandedWidth),
                layout: Self.expandedLayout(for: WidgetRuntime.shared)
            )
        } else {
            panel = geometry.compactSize
        }
        // 面板在窗内水平居中、贴顶（AppKit 原点左下）。
        let interactive = CGRect(
            x: (windowFrame.width - panel.width) / 2,
            y: windowFrame.height - panel.height,
            width: panel.width,
            height: panel.height
        )
        hitTestView.interactiveFrame = interactive
        window.interactiveFrameInWindow = interactive
        let fields: [String: Any] = [
            "expanded": isExpanded,
            "vmExpanded": viewModel.isExpanded,
            "x": Int(interactive.origin.x),
            "y": Int(interactive.origin.y),
            "w": Int(interactive.width),
            "h": Int(interactive.height),
            "clickThrough": window.ignoresMouseEvents,
            "controlDeck": WidgetRuntime.shared.isControlDeckPage,
            "layout": "\(Self.expandedLayout(for: WidgetRuntime.shared))"
        ]
        if WidgetRuntime.shared.isControlDeckPage || isExpanded {
            AppLog.info("Overlay", "可点区域已更新", fields)
        } else {
            AppLog.debug("Overlay", "可点区域已更新", fields)
        }
    }

    private func applyFullscreen(_ fullscreen: Bool) {
        let shouldHide = fullscreen && settings.hideInFullscreen
        viewModel.isHiddenForFullscreen = shouldHide
        if shouldHide {
            collapseWorkItem?.cancel()
            isPointerOverIsland = false
            setClickThrough(true, reason: "fullscreenHide")
            if viewModel.isExpanded {
                viewModel.collapse()
            }
        }
        AppLog.info("Overlay", shouldHide ? "全屏隐藏岛" : "全屏恢复岛", [
            "fullscreen": fullscreen,
            "setting": settings.hideInFullscreen
        ])
        updateVisibility()
    }

    private func updateVisibility() {
        let show = viewModel.isVisibleOnDisplay && !viewModel.isHiddenForFullscreen
        if show {
            window.alphaValue = 1
            window.orderFrontRegardless()
            // 下一帧 poll 会按指针位置决定是否穿透；默认先穿透，避免启动即挡点击。
            if !isPointerOverIsland {
                setClickThrough(true, reason: "shownIdle")
            }
        } else if viewModel.isVisibleOnDisplay, viewModel.isHiddenForFullscreen {
            // 真正移出屏幕层级，避免仍挡事件；常驻黑块本身也看不见，靠「悬停无法展开」验证。
            setClickThrough(true, reason: "orderOutFullscreen")
            window.alphaValue = 0
            window.orderOut(nil)
        } else {
            setClickThrough(true, reason: "orderOut")
            window.orderOut(nil)
        }
    }
}
