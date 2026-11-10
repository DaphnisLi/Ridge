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
    /// 左键按住且从岛上开始：拖动期间钉住展开（含 ScrollView / 滑条，不依赖翻页手势）。
    private var pointerDragHoldingExpand = false
    /// 控制台列表最近一次纵滑时间；宽限内钉住展开（滚轮无左键）。
    private var lastContentScrollAt: Date = .distantPast
    /// 系统拖文件进入岛 / 悬停在货架投放区：钉住展开，避免展开收起来回闪。
    private var isShelfFileDragPinned = false
    /// SwiftUI 货架 `.onDrop(isTargeted:)` 命中中。
    private var isShelfDropTargeted = false
    /// 拖文件接近货架时临时抬高层级，便于抢到投放命中。
    private var isShelfDragElevated = false
    /// OCR 全屏遮罩为 screenSaver 级；引导 tip 须抬到其上方才看得见，且保持穿透。
    private var isOCRCaptureElevated = false
    /// 取色 / OCR 进行中：强制整窗穿透，且禁止悬停再展开，避免挡系统放大镜或吞掉 mouseUp。
    private var isExternalPointerToolActive = false
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

        fullscreenMonitor.onChange = { [weak self] fullscreen, systemOverlay in
            self?.applyFullscreen(fullscreen || systemOverlay)
        }
        fullscreenMonitor.start()

        appearanceObserver = viewModel.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.handleAppearanceChange(appearance)
            }

        viewModel.$panelSize
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] size in
                AppLog.debug("Overlay", "面板尺寸变更，刷新可点区", [
                    "w": size.width,
                    "h": size.height
                ])
                self?.updateInteractiveFrame()
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

        // 翻页：控制台内换模块，或滑到番茄页时立刻套对应画布（避免沿用上一页 300×660 / 刘海 30）。
        WidgetRuntime.shared.$activeID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in
                guard let self else { return }
                self.viewModel.allowPanelShrink(for: 0.7, reason: "activeID")
                if id == FocusTimerWidget.manifest.id {
                    self.applyFocusTimerPanelSizeIfNeeded(reason: "page")
                }
                self.updateInteractiveFrame()
                self.applyWindowFrame(animated: false)
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

        FocusTimerSession.shared.$phase
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] phase in
                AppLog.info("Island", "番茄计时态切换，刷新收起尺寸", ["phase": phase.rawValue])
                self?.viewModel.allowPanelShrink(for: 0.7, reason: "focusPhase")
                // 终局等比进行中更高：立刻套画布，避免 Preference 仍按 80pt 矮框裁掉备注热区。
                self?.applyFocusTimerPanelSizeIfNeeded(phase: phase, reason: "phase")
                self?.updateInteractiveFrame()
                self?.applyWindowFrame(animated: true)
            }
            .store(in: &settingsObservers)

        // 电量页台数变化：≤3 一行高 / >3 两行高。
        BatterySession.shared.$devices
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] count in
                guard Self.isBatteryControlDeckPage(WidgetRuntime.shared) else { return }
                AppLog.info("Island", "电量外设台数变化，刷新岛高", [
                    "devices": count,
                    "layout": "\(NotchGeometry.controlDeckBatteryLayout(deviceCount: count))"
                ])
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

    /// 设置窗打开且钉住展开真岛（仅显式需要实时预览时调用；默认开设置用 `beginSettingsSessionCollapsed`）。
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
        // OCR / 货架拖入会把岛抬到 screenSaver/popUpMenu，盖住设置红灯且未穿透时整窗假死。
        resetTransientWindowElevation(reason: "settingsOpen")
        setClickThrough(true, reason: "settingsOpen")
        if viewModel.isExpanded {
            viewModel.collapse()
            applyWindowFrame(animated: true)
            updateInteractiveFrame()
        }
        AppLog.warn("Island", "设置会话：保持收起", [
            "expanded": false,
            "clickThrough": window.ignoresMouseEvents
        ])
    }

    /// 恢复 resting 层级（设置打开 / 关窗时调用）。
    private func resetTransientWindowElevation(reason: String) {
        guard isShelfDragElevated || isOCRCaptureElevated else { return }
        isShelfDragElevated = false
        isOCRCaptureElevated = false
        isShelfFileDragPinned = false
        window.level = islandRestingLevel
        AppLog.warn("Island", "恢复岛窗 resting 层级", [
            "reason": reason,
            "level": window.level.rawValue
        ])
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
            resetTransientWindowElevation(reason: "settingsClose")
        }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        AppLog.warn("Island", "设置页实时预览结束", [
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
        let shelfDropExpand = Self.isShelfDropExpandReason(reason)
        // 已展开时仍要刷番茄画布：进行中→终局不会再走展开，否则 Preference 矮框会一直压住备注热区。
        if viewModel.isExpanded {
            // 短提示替换（取色/OCR →「已复制」等）：必须允许缩宽，否则卡在上一尺寸，短条顶距把内容顶出可视区。
            if reason.contains("islandNotice") {
                viewModel.allowPanelShrink(for: 0.8, reason: "expandAlready:\(reason)")
                AppLog.warn("Island", "通知替换：已允许面板缩小", ["reason": reason])
            }
            if reason.contains("focusTimer") {
                applyFocusTimerPanelSizeIfNeeded(reason: "expandAlready:\(reason)")
            } else if shelfDropExpand {
                applyShelfDropPanelSizeIfNeeded(reason: "expandAlready:\(reason)")
            }
            updateInteractiveFrame(expanded: true)
            // 展开不抢前台（见 IslandFocusPolicy）；文本框点击时再 prepare。
            if IslandFocusPolicy.shouldActivateAppOnExpand {
                ensureIslandInteractionReady(reason: "expandAlready:\(reason)")
            } else {
                AppLog.debug("Overlay", "已展开：跳过抢前台", [
                    "reason": reason,
                    "shelfDrop": shelfDropExpand,
                    "externalTool": isExternalPointerToolActive
                ])
            }
            return
        }
        AppLog.info("Island", "展开灵动岛", [
            "reason": reason,
            "expanded": true,
            "settingsSession": isSettingsSessionActive,
            "settingsPreview": isSettingsLivePreview,
            "prevKey": Self.describeKeyWindow(),
            "active": WidgetRuntime.shared.activeID ?? "nil"
        ])
        viewModel.expand()
        // 仅当前页是番茄时写入番茄画布；媒体展开勿套番茄尺寸。
        applyFocusTimerPanelSizeIfNeeded(reason: "expand:\(reason)")
        if shelfDropExpand {
            applyShelfDropPanelSizeIfNeeded(reason: "expand:\(reason)")
        }
        // 不依赖 Combine 时序：展开后立刻把可点区扩到面板，否则仍是刘海 171×30，控制台点全落空。
        updateInteractiveFrame(expanded: true)
        if IslandFocusPolicy.shouldActivateAppOnExpand {
            ensureIslandInteractionReady(reason: "expand:\(reason)")
        } else {
            AppLog.debug("Overlay", "展开：跳过抢前台", [
                "reason": reason,
                "shelfDrop": shelfDropExpand,
                "externalTool": isExternalPointerToolActive
            ])
        }
        startScrollPagingMonitors()
    }

    /// 货架拖文件展开 / 投放：勿 `NSApp.activate`，否则系统会取消跨 App 拖放。
    private static func isShelfDropExpandReason(_ reason: String) -> Bool {
        reason.hasPrefix("shelfDrop")
    }

    /// 拖入暂存态立刻写成控制台画布，避免切掉 IslandBody 后 Preference 停在刘海尺寸。
    private func applyShelfDropPanelSizeIfNeeded(reason: String) {
        let size = CGSize(
            width: NotchGeometry.controlDeckPreferredWidth,
            height: NotchGeometry.controlDeckMinHeight
        )
        viewModel.applyMeasuredPanelSize(size)
        updateInteractiveFrame(expanded: true)
        AppLog.info("Island", "货架拖入：已套用控制台面板尺寸", [
            "reason": reason,
            "w": Int(size.width),
            "h": Int(size.height),
            "panelW": Int(viewModel.panelSize.width),
            "panelH": Int(viewModel.panelSize.height)
        ])
    }

    /// 当前是番茄页时按 phase 写入内容画布尺寸。
    /// 终局必须抬高可点框：停在进行中 ~80pt 时备注落在 interactiveFrame 外，表现为「点不了输入」。
    private func applyFocusTimerPanelSizeIfNeeded(
        phase: FocusTimerPhase? = nil,
        reason: String
    ) {
        guard WidgetRuntime.shared.activeID == FocusTimerWidget.manifest.id else { return }
        let resolved = phase ?? FocusTimerSession.shared.phase
        // 终局即使尚未 expand 也先写入，避免首帧沿用刘海 30pt / 进行中 80pt。
        guard viewModel.isExpanded
            || reason.hasPrefix("expand:")
            || resolved == .completed
            || reason == "phase"
            || reason == "page"
        else { return }
        let size = FocusTimerContentSize.panelSize(
            phase: resolved,
            notchHeight: viewModel.notchHeight
        )
        viewModel.applyMeasuredPanelSize(size)
        updateInteractiveFrame(expanded: viewModel.isExpanded || resolved == .completed)
        AppLog.warn("Island", "番茄面板尺寸已套用", [
            "reason": reason,
            "phase": resolved.rawValue,
            "w": Int(size.width),
            "h": Int(size.height),
            "panelW": Int(viewModel.panelSize.width),
            "panelH": Int(viewModel.panelSize.height)
        ])
    }

    /// 计时结束专用：保证切页 + 展开后可点区立刻覆盖终局备注。
    func applyFocusTimerCompletedLayout(reason: String) {
        applyFocusTimerPanelSizeIfNeeded(phase: .completed, reason: reason)
        updateInteractiveFrame(expanded: true)
        // 终局备注点输入框时再 prepare；此处 activate 会抢走正在用的其它 App。
        AppLog.debug("Overlay", "番茄终局布局：不抢前台", ["reason": reason])
    }

    /// 进入取色 / OCR：收岛、清按住态、强制穿透，并挡住悬停展开。
    func beginExternalPointerTool(reason: String) {
        isExternalPointerToolActive = true
        isMouseDownInIsland = false
        pointerDragHoldingExpand = false
        isPointerOverIsland = false
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if viewModel.isExpanded {
            collapse(reason: reason)
        }
        setClickThrough(true, reason: "beginExternalTool:\(reason)")
        if window.isKeyWindow {
            window.resignKey()
        }
        demoteIslandInteractionIfNeeded(reason: "beginExternalTool:\(reason)")
        // OCR 遮罩盖住 status 级岛窗；抬到 screenSaver 之上才能看见引导 tip。
        setOCRCaptureWindowElevation(reason.contains("OCR") || reason.contains("ocr"))
        AppLog.warn("Overlay", "外部指针工具开始", [
            "reason": reason,
            "clickThrough": window.ignoresMouseEvents,
            "ocrElevated": isOCRCaptureElevated
        ])
    }

    /// 短提示上岛前预备尺寸：在 `IslandNoticeCenter.present` 改内容之前调用，避免 Preference 先拒缩。
    func prepareShortNoticeLayout(reason: String) {
        let size = IslandChrome.preparedShortTipPanelSize(
            notchWidth: viewModel.notchWidth,
            notchHeight: viewModel.notchHeight
        )
        viewModel.forcePanelSize(size, reason: reason)
        if viewModel.isExpanded {
            updateInteractiveFrame(expanded: true)
        }
        AppLog.warn("Island", "短通知布局已预备", [
            "reason": reason,
            "w": Int(size.width),
            "h": Int(size.height)
        ])
    }

    /// 会议翼 tip 上岛前强制宽面板：否则可点区停在刘海/短条，右翼「进入」点穿到下层。
    func prepareMeetingWingNoticeLayout(reason: String) {
        let notchW = max(viewModel.notchWidth, 110)
        let size = IslandChrome.preparedWingTipPanelSize(
            notchWidth: viewModel.notchWidth,
            notchHeight: viewModel.notchHeight
        )
        viewModel.forcePanelSize(size, reason: reason)
        if viewModel.isExpanded {
            updateInteractiveFrame(expanded: true)
        } else {
            // 尚未展开时也先写可点框，避免首击落在刘海外被 HitTest 放行。
            updateInteractiveFrame(expanded: true)
        }
        AppLog.warn("Island", "会议翼通知布局已预备", [
            "reason": reason,
            "w": Int(size.width),
            "h": Int(size.height),
            "notchW": Int(notchW)
        ])
    }

    /// 取色 / OCR 结束：清按住钉住。若仍展开（如瞬时通知）只恢复按悬停逻辑穿透，不再强行收岛。
    func endExternalPointerTool(reason: String) {
        isExternalPointerToolActive = false
        isMouseDownInIsland = false
        setOCRCaptureWindowElevation(false)
        NSApp.discardEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            before: nil
        )
        let mouse = NSEvent.mouseLocation
        let over: Bool
        if let geometry {
            over = pointerIslandHit(
                mouse: mouse,
                geometry: geometry,
                expanded: viewModel.isExpanded
            ).interactive
        } else {
            over = false
        }
        if !over {
            isPointerOverIsland = false
            setClickThrough(true, reason: "endExternalTool:\(reason)")
            if window.isKeyWindow, !viewModel.isExpanded {
                window.resignKey()
                demoteIslandInteractionIfNeeded(reason: "endExternalTool:\(reason)")
            }
        }
        AppLog.warn("Overlay", "外部指针工具结束", [
            "reason": reason,
            "overInteractive": over,
            "expanded": viewModel.isExpanded,
            "clickThrough": window.ignoresMouseEvents
        ])
    }

    func collapse(reason: String) {
        guard viewModel.isExpanded else { return }
        pointerDragHoldingExpand = false
        isMouseDownInIsland = false
        if isSettingsLivePreview, reason != "settingsPreviewEnd" {
            AppLog.debug("Island", "设置预览中，忽略收起", ["reason": reason])
            return
        }
        // 仅投放区仍命中时挡收起；指针已离开则允许 hoverEnd 收起。
        if isShelfDropTargeted, reason == "hoverEnd" {
            AppLog.debug("Island", "货架投放区命中中，忽略收起", ["targeted": true])
            return
        }
        // 会议 / 久坐等常驻提示：移开指针不得收岛（须入会 / 点掉 / 状态结束）。
        if reason == "hoverEnd",
           let notice = IslandNoticeCenter.shared.current,
           notice.keepsExpandedWithoutHover
        {
            AppLog.debug("Island", "常驻提示中，忽略悬停收起", [
                "notice": notice.id,
                "source": notice.sourceTag
            ])
            return
        }
        // 指针离开：正在编辑则先卸焦再收；避免「点输入框瞬间误判离开」时直接 dismiss 终局。
        if reason == "hoverEnd", IslandInteractionFocus.isEditing(in: window) {
            _ = window.makeFirstResponder(nil)
            AppLog.warn("Island", "指针离开，已结束文本编辑并继续收起")
        }
        AppLog.info("Island", "收起灵动岛", [
            "reason": reason,
            "expanded": false,
            "wasKey": window.isKeyWindow,
            "key": Self.describeKeyWindow()
        ])
        // 番茄终局：收起不丢已入库记录，回到选时；备注需点「保存」才会写入。
        if FocusTimerSession.shared.phase == .completed {
            FocusTimerSession.shared.dismissCompletion()
        }
        viewModel.collapse()
        updateInteractiveFrame(expanded: false)
        stopScrollPagingMonitors()
        scrollAccumX = 0
        // 媒体自动抢页不写「上次浏览」；收岛后拨回用户手势停留页，下次悬停仍进该页。
        if reason != "settingsPreviewEnd" {
            WidgetRuntime.shared.restoreRememberedBrowseAfterCollapse(reason: reason)
        }
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
        // 已在主 RunLoop：直接回调，禁止每帧 `Task { @MainActor }`（长跑会堆满调度线程）。
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
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

        // 取色 / OCR：整窗强制穿透，且不因悬停展开。
        if isExternalPointerToolActive {
            isPointerOverIsland = false
            setClickThrough(true, reason: "externalPointerTool")
            return
        }

        // 设置窗与展开岛常在屏幕上方重叠；命中设置窗时必须穿透，否则关闭按钮/输入会被岛吞掉。
        // 用 isSettingsPresented（非仅 session）：开窗同步标记、关窗先清标记，避免竞态假死。
        if MenuBarController.shared?.isPointerOverPresentedSettings(mouse) == true {
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

        // 可点 / 保展开都以当前页可视面板为准；保展开略外扩，避免贴边抖动误收。
        let hit = pointerIslandHit(
            mouse: mouse,
            geometry: geometry,
            expanded: viewModel.isExpanded
        )
        let overInteractive = hit.interactive
        let overRetention = hit.retention
        let fileDrag = Self.isFileDragInProgress()
        let shelfEnabled = ControlDeckSettings.shared.isModuleEnabled("shelf")
        // 用「控制台展开框」作磁吸区：拖文件靠近时提前展开，不必顶到屏幕最上沿
        // （顶边会触发系统调度中心 / 空间切换，优先级高于第三方窗）。
        let approach = shelfEnabled && fileDrag
            && pointerIsInShelfDropApproachZone(mouse: mouse, geometry: geometry)

        // 左键从岛上按下后拖出：在松开前不收岛（翻页手势 / ScrollView / 滑条都算）。
        let leftDown = NSEvent.pressedMouseButtons & (1 << 0) != 0
        if leftDown {
            if overInteractive || overRetention || pointerDragHoldingExpand || isMouseDownInIsland {
                if !pointerDragHoldingExpand {
                    AppLog.debug("Island", "按住拖动：钉住展开", [
                        "interactive": overInteractive,
                        "retention": overRetention,
                        "panelW": Int(viewModel.panelSize.width),
                        "panelH": Int(viewModel.panelSize.height)
                    ])
                }
                pointerDragHoldingExpand = true
            }
        } else if pointerDragHoldingExpand {
            pointerDragHoldingExpand = false
            AppLog.debug("Island", "按住拖动：已松开")
        }
        let dragHold = isMouseDownInIsland || pointerDragHoldingExpand
        let scrollHold = IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
            lastScrollAt: lastContentScrollAt
        )

        // 仅在「接近 / 在岛上 / 投放区命中」且拖文件进行中时钉住；驶出即解除。
        let wantShelfHold = shelfEnabled
            && (overRetention || isShelfDropTargeted || approach)
            && (fileDrag || isShelfDropTargeted)
        if isShelfFileDragPinned != wantShelfHold {
            isShelfFileDragPinned = wantShelfHold
            if wantShelfHold {
                ControlDeckSettings.shared.focusShelfForDrop()
                AppLog.info("Island", "货架拖入：钉住展开", [
                    "interactive": overInteractive,
                    "retention": overRetention,
                    "targeted": isShelfDropTargeted,
                    "approach": approach
                ])
            } else {
                AppLog.info("Island", "货架拖入：解除钉住", [
                    "interactive": overInteractive,
                    "retention": overRetention,
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
        let shouldIgnore = !overInteractive && !dragHold && !shelfHold
        setClickThrough(
            shouldIgnore,
            reason: shelfHold
                ? "shelfDropHold"
                : (overInteractive ? "pointerOver" : (dragHold ? "dragHold" : "pointerAway"))
        )

        if isSettingsLivePreview {
            isPointerOverIsland = overRetention
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
                expand(reason: approach && !overRetention ? "shelfDropApproach" : "shelfDrop")
            } else if IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: viewModel.panelSize,
                notch: CGSize(width: viewModel.notchWidth, height: viewModel.notchHeight),
                isExpanded: true
            ) {
                // 已展开但仍是刘海尺寸：补套控制台画布（常见于暂存区切掉了 Preference 上报）。
                applyShelfDropPanelSizeIfNeeded(reason: "shelfHoldResize")
            }
            isPointerOverIsland = overRetention || isShelfDropTargeted || approach
            return
        }

        // 按住拖动 / 列表纵滑宽限内：保持展开，避免滚一半指针微移就收岛。
        if dragHold || scrollHold {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            isPointerOverIsland = true
            if !viewModel.isExpanded {
                expand(reason: dragHold ? "dragHold" : "scrollHold")
            }
            return
        }

        if overRetention == isPointerOverIsland { return }
        isPointerOverIsland = overRetention

        if overRetention {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            // 无面板/已点进实况上岛时，禁止仅靠移入展开（瞬时提示可程序 expand，悬停仅保展开）。
            if viewModel.isExpanded {
                return
            }
            if WidgetRuntime.shared.allowsHoverExpand {
                expand(reason: "hover")
            } else {
                AppLog.debug("Island", "无面板上岛，忽略悬停展开", [
                    "page": WidgetRuntime.shared.activeID ?? "nil",
                    "pages": WidgetRuntime.shared.pageIDs.count,
                    "notice": IslandNoticeCenter.shared.current?.id ?? ""
                ])
            }
        } else if let notice = IslandNoticeCenter.shared.current,
                  notice.keepsExpandedWithoutHover,
                  viewModel.isExpanded
        {
            // 会议等常驻提示：离开热区也不安排收起，岛保持展开。
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
        } else {
            AppLog.warn("Island", "指针离开保展开区，安排收起", [
                "interactive": overInteractive,
                "panelW": Int(viewModel.panelSize.width),
                "panelH": Int(viewModel.panelSize.height),
                "notchW": Int(geometry.notchWidth),
                "notchH": Int(geometry.notchHeight),
                "page": WidgetRuntime.shared.activeID ?? "nil",
                "controlDeck": WidgetRuntime.shared.isControlDeckPage
            ])
            scheduleCollapse()
        }
    }

    /// 控制台 `AlwaysVisibleScrollView` / 纵滑滚轮：刷新保展开宽限。
    func noteContentScrollActivity(reason: String) {
        lastContentScrollAt = Date()
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if viewModel.isExpanded {
            isPointerOverIsland = true
        }
        AppLog.debug("Island", "内容滚动：保展开", [
            "reason": reason,
            "expanded": viewModel.isExpanded,
            "graceMs": Int(IslandExpandedPanelPolicy.contentScrollHoldGrace * 1000)
        ])
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
        // 设置展示中禁止抬层，否则盖住设置红灯。
        if elevated, MenuBarController.shared?.isSettingsPresented == true {
            AppLog.warn("Island", "设置展示中跳过货架抬层")
            return
        }
        isShelfDragElevated = elevated
        if elevated {
            // 抬到弹出菜单级，仍低于系统拖影；提高相对其它浮层的投放命中机会。
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            window.orderFrontRegardless()
            AppLog.debug("Island", "货架拖入：抬高窗口层级")
        } else if isOCRCaptureElevated {
            // OCR 仍在：保持高于遮罩，勿掉回 resting。
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
            AppLog.debug("Island", "货架拖入结束：仍保持 OCR 抬高层级")
        } else {
            window.level = islandRestingLevel
            AppLog.debug("Island", "货架拖入：恢复窗口层级")
        }
    }

    private func setOCRCaptureWindowElevation(_ elevated: Bool) {
        guard isOCRCaptureElevated != elevated else { return }
        if elevated, MenuBarController.shared?.isSettingsPresented == true {
            AppLog.warn("Island", "设置展示中跳过 OCR 抬层")
            return
        }
        isOCRCaptureElevated = elevated
        if elevated {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
            window.orderFrontRegardless()
            AppLog.warn("Island", "OCR 框选：岛窗抬到遮罩之上", [
                "level": window.level.rawValue
            ])
        } else if isShelfDragElevated {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            AppLog.debug("Island", "OCR 结束：仍保持货架拖入层级")
        } else {
            window.level = islandRestingLevel
            AppLog.warn("Island", "OCR 框选：岛窗恢复 resting 层级")
        }
    }

    /// `true` = 整窗点击穿透到下层 App；悬停进入可交互区后再关闭穿透。
    private func setClickThrough(_ enabled: Bool, reason: String) {
        guard window.ignoresMouseEvents != enabled else { return }
        window.ignoresMouseEvents = enabled
        // 关穿透：只收鼠标，禁止 activate（会议 tip 贴顶时指针常扫过，一悬停就抢前台）。
        // 开穿透：立刻 resignKey + 降 accessory，否则常驻展开会把键盘粘在 Ridge 上。
        if enabled, IslandFocusPolicy.shouldResignKeyWhenEnablingClickThrough {
            releaseIslandKeyboardFocusIfNeeded(reason: "clickThroughOn:\(reason)")
        } else if !enabled, IslandFocusPolicy.shouldActivateAppWhenDisablingClickThrough {
            ensureIslandInteractionReady(reason: "clickThroughOff:\(reason)")
        } else if !enabled {
            AppLog.debug("Overlay", "关闭穿透但不抢前台", [
                "reason": reason,
                "expanded": viewModel.isExpanded,
                "key": window.isKeyWindow,
                "appActive": NSApp.isActive
            ])
        }
        let meetingTip = IslandNoticeCenter.shared.current?.usesNotchWingChrome == true
        // 会议 tip 穿透切换必须落盘：按钮点穿多半是可点区过窄 + 仍穿透。
        if meetingTip || WidgetRuntime.shared.isControlDeckPage {
            AppLog.warn("Overlay", enabled ? "开启点击穿透" : "关闭点击穿透", [
                "reason": reason,
                "expanded": viewModel.isExpanded,
                "meetingTip": meetingTip,
                "panelW": Int(viewModel.panelSize.width),
                "panelH": Int(viewModel.panelSize.height),
                "islandKey": window.isKeyWindow,
                "appActive": NSApp.isActive
            ])
        } else {
            AppLog.debug("Overlay", enabled ? "开启点击穿透" : "关闭点击穿透", [
                "reason": reason,
                "expanded": viewModel.isExpanded,
                "islandKey": window.isKeyWindow,
                "appActive": NSApp.isActive
            ])
        }
    }

    /// 文本输入等少数路径才升 regular + activate；悬停 / 普通点击禁止走这里。
    private func ensureIslandInteractionReady(reason: String) {
        if isSettingsSessionActive {
            AppLog.debug("Overlay", "设置会话中跳过岛激活", [
                "reason": reason,
                "appActive": NSApp.isActive,
                "key": Self.describeKeyWindow()
            ])
            return
        }
        if isExternalPointerToolActive {
            AppLog.warn("Overlay", "外部指针工具中跳过岛激活", [
                "reason": reason
            ])
            return
        }
        IslandInteractionFocus.prepare(window: window, reason: "islandReady:\(reason)")
    }

    /// 指针离开可点区 / 收起：交还 key，避免其它 App 点不进输入框。
    private func releaseIslandKeyboardFocusIfNeeded(reason: String) {
        if isSettingsSessionActive { return }
        if MenuBarController.shared?.settingsWindow != nil { return }
        if IslandInteractionFocus.isEditing(in: window) {
            _ = window.makeFirstResponder(nil)
            AppLog.warn("Overlay", "穿透前结束岛内编辑", ["reason": reason])
        }
        if window.isKeyWindow {
            window.resignKey()
            AppLog.info("Overlay", "已 resignKey 交还键盘", [
                "reason": reason,
                "key": Self.describeKeyWindow(),
                "appActive": NSApp.isActive
            ])
        }
        demoteIslandInteractionIfNeeded(reason: reason)
    }

    /// 收起后若设置窗未开，降回 accessory，避免常驻 Dock。
    private func demoteIslandInteractionIfNeeded(reason: String) {
        if isSettingsSessionActive { return }
        if MenuBarController.shared?.settingsWindow != nil { return }
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("Overlay", "降回 accessory", [
            "reason": reason,
            "appActive": NSApp.isActive
        ])
    }

    private struct IslandPointerHit {
        /// 当前页可视面板（含刘海）：决定是否接收点击。
        let interactive: Bool
        /// 可视面板略外扩：决定是否保持展开；离开后应收岛。
        let retention: Bool
    }

    /// 刘海始终算命中；展开后可点 / 保展开跟内容撑开的 `panelSize` 走（见 `IslandExpandedPanelPolicy`）。
    private func pointerIslandHit(
        mouse: NSPoint,
        geometry: NotchGeometry,
        expanded: Bool
    ) -> IslandPointerHit {
        // 保展开用「稳定大面板」尺寸，避免 Preference 误缩成刘海后下半截一移就收。
        let retentionSize = viewModel.retentionPanelSize(
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight
        )
        var pageBody = geometry.panelFrameOnScreen(size: viewModel.panelSize)
        var retentionBody = geometry.panelFrameOnScreen(size: retentionSize)
        if retentionSize != viewModel.panelSize, expanded {
            AppLog.warn("Island", "保展开改用稳定面板尺寸", [
                "panelW": Int(viewModel.panelSize.width),
                "panelH": Int(viewModel.panelSize.height),
                "stableW": Int(retentionSize.width),
                "stableH": Int(retentionSize.height)
            ])
        }
        // 刚从控制台翻到矮页：短暂并入大热区，避免指针还在原下半截被当成离开。
        if expanded, let boost = hoverLayoutBoost, Date() < hoverLayoutBoostUntil {
            let width = CGFloat(IslandSettings.shared.expandedWidth)
            let boostFrame = geometry.expandedFrameOnScreen(width: width, layout: boost)
            pageBody = pageBody.union(boostFrame)
            retentionBody = retentionBody.union(boostFrame)
        } else if hoverLayoutBoost != nil {
            hoverLayoutBoost = nil
        }

        let retentionFrame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: geometry.notchFrame,
            panelFrame: retentionBody,
            expanded: expanded
        )
        let interactiveFrame = expanded
            ? pageBody.insetBy(dx: -2, dy: -2).union(geometry.notchFrame.insetBy(dx: -4, dy: -2))
            : geometry.notchFrame.insetBy(dx: -4, dy: -2)

        return IslandPointerHit(
            interactive: interactiveFrame.contains(mouse),
            retention: retentionFrame.contains(mouse)
        )
    }

    private func pointerIsOverIsland(
        mouse: NSPoint,
        geometry: NotchGeometry,
        expanded: Bool
    ) -> Bool {
        pointerIslandHit(mouse: mouse, geometry: geometry, expanded: expanded).retention
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        // 刚翻页时高度会变，给指针一点时间落在新面板上，避免误收；整体偏短，收岛更跟手。
        let delay: TimeInterval = Date().timeIntervalSince(lastPageSwipeAt) < 0.45 ? 0.22 : 0.10
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 会议等常驻提示：宽限到期也不收。
            if let notice = IslandNoticeCenter.shared.current,
               notice.keepsExpandedWithoutHover
            {
                AppLog.debug("Island", "收起前复查：常驻提示，取消收起", ["notice": notice.id])
                return
            }
            // 收起前再确认一次，避免边缘抖动。
            guard let geometry else {
                self.collapse(reason: "hoverEnd")
                return
            }
            let mouse = NSEvent.mouseLocation
            // 设置窗盖住岛展开区时，不算「还在岛上」（否则设计页永远收不起来）。
            if self.isPointerOverSettingsWindow(mouse), !self.isSettingsLivePreview {
                self.isPointerOverIsland = false
                AppLog.info("Island", "收起前复查：指针在设置窗", ["reason": "hoverEnd"])
                self.collapse(reason: "hoverEnd")
                return
            }
            let hit = self.pointerIslandHit(
                mouse: mouse,
                geometry: geometry,
                expanded: true
            )
            if hit.retention {
                self.isPointerOverIsland = true
                AppLog.debug("Island", "收起前复查：仍在保展开区，取消收起", [
                    "interactive": hit.interactive
                ])
                return
            }
            // 编辑中也收：collapse(hoverEnd) 会先卸焦再收起；勿在此挡收，否则移出岛外岛不消失。
            // 复查时若仍按住左键，视为拖动未结束，不收。
            if NSEvent.pressedMouseButtons & (1 << 0) != 0 {
                self.pointerDragHoldingExpand = true
                self.isPointerOverIsland = true
                AppLog.warn("Island", "收起前复查：仍在拖动，取消收起", [
                    "panelW": Int(self.viewModel.panelSize.width),
                    "panelH": Int(self.viewModel.panelSize.height)
                ])
                return
            }
            if IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: self.lastContentScrollAt
            ) {
                self.isPointerOverIsland = true
                AppLog.warn("Island", "收起前复查：内容滚动宽限内，取消收起", [
                    "panelW": Int(self.viewModel.panelSize.width),
                    "panelH": Int(self.viewModel.panelSize.height)
                ])
                return
            }
            AppLog.warn("Island", "收起前复查：已离开保展开区", [
                "interactive": hit.interactive,
                "panelW": Int(self.viewModel.panelSize.width),
                "panelH": Int(self.viewModel.panelSize.height),
                "notchW": Int(geometry.notchWidth),
                "notchH": Int(geometry.notchHeight),
                "editing": IslandInteractionFocus.isEditing(in: self.window)
            ])
            self.collapse(reason: "hoverEnd")
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func isPointerOverSettingsWindow(_ mouse: NSPoint) -> Bool {
        MenuBarController.shared?.isPointerOverPresentedSettings(mouse) == true
    }

    private static func expandedLayout(for runtime: WidgetRuntime) -> NotchGeometry.ExpandedLayout {
        if runtime.isControlDeckPage {
            if isBatteryControlDeckPage(runtime) {
                return NotchGeometry.controlDeckBatteryLayout(
                    deviceCount: BatterySession.shared.devices.count
                )
            }
            return .controlDeck
        }
        if runtime.isTransientNoticePage { return .notice }
        if runtime.isComboPage { return .combo }
        if runtime.activeID == FocusTimerWidget.manifest.id { return .focusTimer }
        return .standard
    }

    private static func isBatteryControlDeckPage(_ runtime: WidgetRuntime) -> Bool {
        if let id = runtime.activeID,
           ControlDeckSettings.Pane.from(pageID: id) == .battery
        {
            return true
        }
        return runtime.isControlDeckPage && ControlDeckSettings.shared.activePane == .battery
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

        // 控制台（电量 / 货架 / 混音）需要纵向滚动：纵滑放行给 AlwaysVisibleScrollView；
        // 仅横滑主导时才翻页。以前整页 return false 导致电量页左右滑失效。
        guard abs(dx) > abs(dy), abs(dx) > 0.05 else {
            if abs(dy) > 0.05 {
                noteContentScrollActivity(reason: "verticalWheel")
            }
            if event.phase == .ended || event.phase == .cancelled {
                scrollAccumX = 0
            }
            return false
        }

        scrollAccumX += dx
        AppLog.debug("Overlay", "触控板横滑累加", [
            "dx": dx,
            "accum": scrollAccumX,
            "phase": event.phase.rawValue,
            "controlDeck": WidgetRuntime.shared.isControlDeckPage
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
        viewModel.allowPanelShrink(for: 0.7, reason: "pageSwipe")
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
            "pageLayout": "\(Self.expandedLayout(for: WidgetRuntime.shared))",
            "page": WidgetRuntime.shared.activeID ?? "nil",
            "boost": hoverLayoutBoost != nil,
            "retention": "pagePadded"
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
        viewModel.maxExpandedWidth = preferred.1.maxExpandedWidth
        if !viewModel.isExpanded {
            viewModel.panelSize = preferred.1.compactSize
        }
        AppLog.info("Notch", "对齐刘海", [
            "reason": reason,
            "display": Int(preferred.1.screenID),
            "notchW": preferred.1.notchWidth,
            "notchH": preferred.1.notchHeight,
            "panelW": viewModel.panelSize.width,
            "panelH": viewModel.panelSize.height,
            "windowW": preferred.1.windowSize.width
        ])
        // 窗口固定最大宽占位；面板由内容测量撑开，在窗内居中。
        applyWindowFrame(animated: false)
        updateVisibility()
    }

    private func handleAppearanceChange(_ appearance: IslandAppearance) {
        AppLog.info("Island", appearance == .expanded ? "切换到展开态" : "切换到常驻态", [
            "expanded": appearance == .expanded
        ])
        // 以 sink 收到的 appearance 为准，避免与 viewModel 时序错位时热区停在刘海尺寸。
        updateInteractiveFrame(expanded: appearance == .expanded)
        // 仅展开时震动；收起保持安静。
        if appearance == .expanded {
            IslandHaptics.play(settings.hapticIntensity)
        }
    }

    private func applyWindowFrame(animated: Bool) {
        guard let geometry else { return }
        _ = animated // 窗体尺寸不跟宽度做 AppKit 动画，避免与 SwiftUI 面板抢裁切。
        viewModel.maxExpandedWidth = geometry.maxExpandedWidth
        // 窗口始终按最大占位；可见面板宽高由内容测量写入 viewModel.panelSize。
        let frame = geometry.windowFrameOnScreen()
        window.setFrame(frame, display: true)
        hostingView?.frame = hitTestView.bounds
        updateInteractiveFrame()
        AppLog.debug("Island", "窗口占位已更新", [
            "windowW": frame.width,
            "windowH": frame.height,
            "panelW": viewModel.panelSize.width,
            "panelH": viewModel.panelSize.height
        ])

        if viewModel.isVisibleOnDisplay && !viewModel.isHiddenForFullscreen {
            window.orderFrontRegardless()
        }
    }

    private func updateInteractiveFrame(expanded: Bool? = nil) {
        guard geometry != nil else { return }
        let windowFrame = window.frame
        let isExpanded = expanded ?? viewModel.isExpanded
        // 展开 / 收起 / 待命一律以内容（或收起几何）写入的 panelSize 为准。
        let panel = viewModel.panelSize
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
            "controlDeck": WidgetRuntime.shared.isControlDeckPage
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
