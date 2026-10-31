import AppKit
import Combine
import SwiftUI

/// 灵动岛窗口控制器：几何对齐、悬停展开、全屏隐藏、多屏降级。
@MainActor
final class IslandController: NSObject {
    let viewModel = IslandViewModel()
    private let settings = IslandSettings.shared
    private let window = IslandWindow.make()
    private let hitTestView = IslandHitTestView()
    private var hostingView: NSHostingView<IslandContentView>?
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

    func start() {
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

        settings.$expandedWidthScale
            .combineLatest(settings.$expandedHeightScale)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .dropFirst()
            .sink { [weak self] width, height in
                guard let self else { return }
                // 收起时只静默改窗体占位，避免常驻黑条跟着动画抖动。
                let animate = self.viewModel.isExpanded
                AppLog.info("Settings", "展开尺寸倍率变更", [
                    "width": width,
                    "height": height,
                    "animate": animate
                ])
                self.applyWindowFrame(animated: animate)
            }
            .store(in: &settingsObservers)

        startHoverPolling()
        relayout(reason: "start")
        AppLog.info("Island", "控制器已启动")
    }

    func stop() {
        stopHoverPolling()
        collapseWorkItem?.cancel()
        fullscreenMonitor.stop()
        displayMonitor.stop()
        appearanceObserver?.cancel()
        settingsObservers.removeAll()
        window.orderOut(nil)
    }

    func expand(reason: String) {
        guard !viewModel.isExpanded else { return }
        AppLog.info("Island", "展开灵动岛", ["reason": reason, "expanded": true])
        viewModel.expand()
    }

    func collapse(reason: String) {
        guard viewModel.isExpanded else { return }
        AppLog.info("Island", "收起灵动岛", ["reason": reason, "expanded": false])
        viewModel.collapse()
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
        let over = Self.pointerIsOverIsland(
            mouse: mouse,
            geometry: geometry,
            expanded: viewModel.isExpanded
        )

        // 窗体始终按展开尺寸占位；收起时刘海以外必须穿透。
        // AppKit 里 contentView.hitTest 返回 nil 不能可靠把点击交给下层，只能用 ignoresMouseEvents。
        setClickThrough(!over, reason: over ? "pointerOver" : "pointerAway")

        if over == isPointerOverIsland { return }
        isPointerOverIsland = over

        if over {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            expand(reason: "hover")
        } else {
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
            let widthScale = CGFloat(IslandSettings.shared.expandedWidthScale)
            let heightScale = CGFloat(IslandSettings.shared.expandedHeightScale)
            let body = geometry.expandedFrameOnScreen(
                widthScale: widthScale,
                heightScale: heightScale
            ).insetBy(dx: -2, dy: -2)
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
        let root = IslandContentView(viewModel: viewModel, settings: settings)
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hostingView = hosting

        hitTestView.wantsLayer = true
        hitTestView.layer?.backgroundColor = NSColor.clear.cgColor
        hitTestView.addSubview(hosting)

        window.contentView = hitTestView
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
        let widthScale = CGFloat(settings.expandedWidthScale)
        let heightScale = CGFloat(settings.expandedHeightScale)
        let expanded = preferred.1.expandedSize(widthScale: widthScale, heightScale: heightScale)
        AppLog.info("Notch", "对齐刘海", [
            "reason": reason,
            "display": Int(preferred.1.screenID),
            "width": preferred.1.notchWidth,
            "height": preferred.1.notchHeight,
            "expandedW": expanded.width,
            "expandedH": expanded.height
        ])
        // 窗口始终按展开尺寸占位，避免悬停时改窗体触发抖动。
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
        let frame = geometry.expandedFrameOnScreen(
            widthScale: CGFloat(settings.expandedWidthScale),
            heightScale: CGFloat(settings.expandedHeightScale)
        )

        let apply = { [weak self] in
            guard let self else { return }
            self.window.setFrame(frame, display: true)
            self.hostingView?.frame = self.hitTestView.bounds
            self.updateInteractiveFrame()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = settings.springDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }

        if viewModel.isVisibleOnDisplay && !viewModel.isHiddenForFullscreen {
            window.orderFrontRegardless()
        }
    }

    private func updateInteractiveFrame() {
        guard let geometry else { return }
        let windowFrame = window.frame
        let interactive: CGRect
        if viewModel.isExpanded {
            interactive = CGRect(origin: .zero, size: windowFrame.size)
        } else {
            let compact = geometry.compactSize
            interactive = CGRect(
                x: (windowFrame.width - compact.width) / 2,
                y: windowFrame.height - compact.height,
                width: compact.width,
                height: compact.height
            )
        }
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
