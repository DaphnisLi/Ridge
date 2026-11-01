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
    private var isPointerOverIsland = false
    private var collapseWorkItem: DispatchWorkItem?
    /// 岛内按下拖拽中：保持接收事件，避免穿透把翻页掐断。
    private var isMouseDownInIsland = false
    private var pagePanRecognizer: NSPanGestureRecognizer?
    /// 触控板横滑：nonactivating Panel 上的 scrollWheel 常被系统送给下层 App，用监视器兜底。
    private var scrollLocalMonitor: Any?
    private var scrollGlobalMonitor: Any?
    private var scrollAccumX: CGFloat = 0
    private var lastPageSwipeAt: Date = .distantPast
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
        applyScreenRecordingVisibility()

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

        settings.$showInScreenRecordings
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyScreenRecordingVisibility()
            }
            .store(in: &settingsObservers)

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
                AppLog.info("Island", "控制台高度切换", ["tall": combo])
                self?.updateInteractiveFrame()
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
        // 设置会话中不抢 key：否则设置刚打开/钉住预览时会被岛抢走焦点，表现为「窗还在却失焦」。
        // 非设置场景仍 makeKey，方便触控板滚轮落到本窗（nonactivatingPanel 不抢其它 App 前台）。
        if isSettingsSessionActive {
            AppLog.info("Island", "展开跳过 makeKey，避免抢走设置焦点", [
                "reason": reason,
                "key": Self.describeKeyWindow()
            ])
        } else {
            window.makeKey()
            AppLog.debug("Island", "展开后 makeKey", [
                "reason": reason,
                "islandKey": window.isKeyWindow,
                "key": Self.describeKeyWindow()
            ])
        }
        startScrollPagingMonitors()
    }

    func collapse(reason: String) {
        guard viewModel.isExpanded else { return }
        if isSettingsLivePreview, reason != "settingsPreviewEnd" {
            AppLog.debug("Island", "设置预览中，忽略收起", ["reason": reason])
            return
        }
        AppLog.info("Island", "收起灵动岛", [
            "reason": reason,
            "expanded": false,
            "wasKey": window.isKeyWindow,
            "key": Self.describeKeyWindow()
        ])
        viewModel.collapse()
        stopScrollPagingMonitors()
        scrollAccumX = 0
        if window.isKeyWindow {
            window.resignKey()
            AppLog.debug("Island", "收起后 resignKey", ["key": Self.describeKeyWindow()])
        }
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
            isPointerOverIsland = false
            if isSettingsLivePreview, !viewModel.isExpanded {
                expand(reason: "settingsPreview")
            }
            return
        }

        let over = Self.pointerIsOverIsland(
            mouse: mouse,
            geometry: geometry,
            expanded: viewModel.isExpanded
        )

        // 窗体始终按展开尺寸占位；收起时刘海以外必须穿透。
        // 拖拽翻页过程中不穿透，否则 mouseDragged / 横滑会被掐断。
        let shouldIgnore = !over && !isMouseDownInIsland
        setClickThrough(shouldIgnore, reason: over ? "pointerOver" : (isMouseDownInIsland ? "dragHold" : "pointerAway"))

        if isSettingsLivePreview {
            isPointerOverIsland = over
            if !viewModel.isExpanded {
                expand(reason: "settingsPreview")
            }
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

    /// `true` = 整窗点击穿透到下层 App；悬停进入可交互区后再关闭穿透。
    private func setClickThrough(_ enabled: Bool, reason: String) {
        guard window.ignoresMouseEvents != enabled else { return }
        window.ignoresMouseEvents = enabled
        AppLog.debug("Overlay", enabled ? "开启点击穿透" : "关闭点击穿透", [
            "reason": reason,
            "expanded": viewModel.isExpanded
        ])
    }

    /// 刘海本体始终算「在岛上」；展开后展开面板区域也算。
    private static func pointerIsOverIsland(
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
            let width = CGFloat(IslandSettings.shared.expandedWidth)
            let body = geometry.expandedFrameOnScreen(width: width)
                .insetBy(dx: -2, dy: -2)
            if body.contains(mouse) {
                return true
            }
        }
        return false
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 收起前再确认一次，避免边缘抖动。
            guard let geometry else {
                self.collapse(reason: "hoverEnd")
                return
            }
            let stillOver = Self.pointerIsOverIsland(
                mouse: NSEvent.mouseLocation,
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
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
        hosting.onHorizontalPageSwipe = { [weak self] offset in
            self?.commitPageSwipe(offset: offset, source: "hostingScroll")
        }
        hostingView = hosting

        hitTestView.wantsLayer = true
        hitTestView.layer?.backgroundColor = NSColor.clear.cgColor
        hitTestView.addSubview(hosting)

        // SwiftUI DragGesture 在 nonactivating Panel 上不可靠；用 AppKit 平移识别拖拽翻页。
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePagePan(_:)))
        hitTestView.addGestureRecognizer(pan)
        pagePanRecognizer = pan

        window.contentView = hitTestView
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
        guard let geometry else { return false }
        guard Self.pointerIsOverIsland(
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
        WidgetRuntime.shared.selectPage(offset: offset)
    }

    @objc private func handlePagePan(_ gr: NSPanGestureRecognizer) {
        switch gr.state {
        case .began:
            isMouseDownInIsland = true
            setClickThrough(false, reason: "panBegan")
        case .ended, .cancelled, .failed:
            defer {
                isMouseDownInIsland = false
                gr.setTranslation(.zero, in: hitTestView)
            }
            guard viewModel.isExpanded else { return }
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
        AppLog.debug("Island", appearance == .expanded ? "切换到展开态" : "切换到常驻态", [
            "expanded": appearance == .expanded
        ])
        // 只更新可点区域；窗体尺寸保持展开上限。
        updateInteractiveFrame()
        IslandHaptics.play(settings.hapticIntensity)
    }

    private func applyWindowFrame(animated: Bool) {
        guard let geometry else { return }
        _ = animated // 窗体尺寸不跟宽度做 AppKit 动画，避免与 SwiftUI 面板抢裁切。
        viewModel.maxExpandedWidth = geometry.maxExpandedWidth
        let requestedW = CGFloat(settings.expandedWidth)
        let combo = WidgetRuntime.shared.isComboPage
        let panel = geometry.expandedSize(width: requestedW, combo: combo)
        if abs(requestedW - panel.width) > 0.5 {
            AppLog.warn("Island", "展开宽度已按屏幕/刘海钳制", [
                "requested": requestedW,
                "usedW": panel.width
            ])
        }
        // 窗口始终 = 最大展开宽 × 组合页高度；面板高度随是否组合页变化。
        let frame = geometry.windowFrameOnScreen()
        window.setFrame(frame, display: true)
        hostingView?.frame = hitTestView.bounds
        updateInteractiveFrame()
        AppLog.debug("Island", "窗口占位已更新", [
            "windowW": frame.width,
            "windowH": frame.height,
            "panelW": panel.width,
            "panelH": panel.height,
            "combo": combo,
            "requestedW": requestedW
        ])

        if viewModel.isVisibleOnDisplay && !viewModel.isHiddenForFullscreen {
            window.orderFrontRegardless()
        }
    }

    private func updateInteractiveFrame() {
        guard let geometry else { return }
        let windowFrame = window.frame
        let panel: CGSize
        if viewModel.isExpanded {
            panel = geometry.expandedSize(
                width: CGFloat(settings.expandedWidth),
                combo: WidgetRuntime.shared.isComboPage
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
        AppLog.debug("Overlay", "可点区域已更新", [
            "expanded": viewModel.isExpanded,
            "x": interactive.origin.x,
            "y": interactive.origin.y,
            "w": interactive.width,
            "h": interactive.height,
            "clickThrough": window.ignoresMouseEvents
        ])
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

    private func applyScreenRecordingVisibility() {
        window.sharingType = settings.showInScreenRecordings ? .readOnly : .none
        AppLog.debug("Overlay", "屏幕录制可见性已应用", [
            "visible": settings.showInScreenRecordings
        ])
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
