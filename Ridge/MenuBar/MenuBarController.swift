import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    /// 供岛在指针落在设置窗上时强制点击穿透，避免挡住设置内按钮。
    private(set) static weak var shared: MenuBarController?

    private var statusItem: NSStatusItem?
    private weak var island: IslandController?
    private var settingsWindowController: NSWindowController?
    private var openSettingsObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var appResignObserver: NSObjectProtocol?
    private var prewarmWorkItem: DispatchWorkItem?
    /// 从打开到 orderOut 全程为 true；勿仅靠 `isVisible`（关窗竞态时岛会误吞关闭按钮）。
    private(set) var isSettingsPresented = false

    /// 当前设置窗（展示中）。
    var settingsWindow: NSWindow? {
        guard isSettingsPresented else { return nil }
        return settingsWindowController?.window
    }

    /// 屏幕坐标是否落在展示中的设置窗上（含标题栏红灯）。
    func isPointerOverPresentedSettings(_ mouse: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard isSettingsPresented,
              let window = settingsWindowController?.window
        else { return false }
        return window.frame.contains(mouse)
    }

    func start(island: IslandController) {
        Self.shared = self
        self.island = island
        // squareLength 比 variableLength 更易点；图标裁切后约 22pt，避免「芝麻粒」。
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // 菜单栏专用线稿（MenuBarIcon），与程序坞彩色 AppIcon 分开；template 随系统外观着色。
            let fromAsset = NSImage(named: "MenuBarIcon")
            let icon = fromAsset
                ?? NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: nil)
            icon?.size = NSSize(width: 22, height: 22)
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.toolTip = "Ridge"
            AppLog.info("Overlay", "菜单栏图标已设置", [
                "asset": fromAsset != nil ? "MenuBarIcon" : "sf.symbol.fallback",
                "pointSize": 22
            ])
        }
        item.menu = buildMenu()
        statusItem = item

        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .ridgeOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openSettings()
            }
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let window = self.settingsWindowController?.window,
                      window.isVisible
                else { return }
                AppLog.info("Settings", "App 失去前台（设置仍打开）", [
                    "settingsKey": window.isKeyWindow,
                    "key": Self.describeKeyWindow()
                ])
                IslandController.shared?.setSettingsWindowFocused(false)
            }
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let window = self?.settingsWindowController?.window,
                      window.isVisible
                else { return }
                AppLog.info("Settings", "App 回到前台（设置仍打开）", [
                    "settingsKey": window.isKeyWindow,
                    "key": Self.describeKeyWindow()
                ])
                guard window.isKeyWindow else { return }
                IslandController.shared?.setSettingsWindowFocused(true)
            }
        }

        // 空闲时预热设置窗，避免第一次点开卡一下。
        let work = DispatchWorkItem { [weak self] in
            self?.prewarmSettingsWindowIfNeeded()
        }
        prewarmWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)

        AppLog.info("Overlay", "菜单栏已就绪")
    }

    func stop() {
        prewarmWorkItem?.cancel()
        prewarmWorkItem = nil
        if let openSettingsObserver {
            NotificationCenter.default.removeObserver(openSettingsObserver)
            self.openSettingsObserver = nil
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settings = NSMenuItem(
            title: L10n.Common.settings,
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: L10n.Common.about,
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let updates = NSMenuItem(
            title: L10n.Common.checkForUpdates,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        let feedback = NSMenuItem(
            title: L10n.Common.sendFeedback,
            action: #selector(sendFeedback),
            keyEquivalent: ""
        )
        feedback.target = self
        menu.addItem(feedback)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: L10n.Common.quitApp,
            action: #selector(quit),
            keyEquivalent: ""
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func openAbout() {
        SettingsNavigator.shared.open(.about)
    }

    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates(userInitiated: true)
    }

    @objc private func sendFeedback() {
        _ = FeedbackService.openMail(includeDiagnostics: true)
    }

    @objc private func openSettings() {
        let openedAt = Date()
        AppLog.warn("Settings", "打开设置窗")
        // 先于 orderFront 标记展示 + 开会话，避免岛窗盖住标题栏时尚未穿透。
        isSettingsPresented = true
        // 设置打开期间进入 regular，才能被 ⌘Tab 切回来；关闭后再变回 accessory。
        promoteForSettingsWindow()
        IslandController.shared?.beginSettingsSessionCollapsed()

        let window = ensureSettingsWindow()
        let screen = Self.activeScreen()
        // 每次打开都套回预设尺寸并相对当前屏居中（避免复用窗留在旧位置/旧宽度）。
        // NavigationSplitView 侧栏会在首帧之后再参与布局，可能把窗往右撑开；
        // 因此先居中一次，orderFront 后再钉尺寸并二次居中。
        applyDefaultSizeAndCenter(window, on: screen)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 先把窗画出来，下一拍再钉岛，避免「建窗 + 展开岛」同帧抢主线程。
        DispatchQueue.main.async {
            self.applyDefaultSizeAndCenter(window, on: screen)
            self.syncIslandPreviewForCurrentSection()
            let visible = screen?.visibleFrame ?? .zero
            let frame = window.frame
            AppLog.warn("Settings", "设置窗已前置", [
                "ms": Int(Date().timeIntervalSince(openedAt) * 1000),
                "section": SettingsNavigator.shared.section.rawValue,
                "frameW": Int(frame.width),
                "leftGap": Int(frame.minX - visible.minX),
                "rightGap": Int(visible.maxX - frame.maxX)
            ])
        }
    }

    /// 隐藏关闭：保留 hosting，下次打开不再冷启动 SwiftUI。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === settingsWindowController?.window else { return true }
        AppLog.warn("Settings", "收到关闭请求")
        // 先摘展示标记并 orderOut：否则清会话后岛仍盖在红灯上，点关闭像卡死。
        isSettingsPresented = false
        sender.orderOut(nil)
        WidgetFlyAnimator.shared.cancel()
        ResourceMonitorSession.shared.setSettingsVisible(false)
        IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
        AppLog.warn("Settings", "设置窗已隐藏（保留实例）")
        demoteAfterSettingsClosed()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === settingsWindowController?.window
        else { return }
        isSettingsPresented = false
        WidgetFlyAnimator.shared.cancel()
        IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
        AppLog.warn("Settings", "设置窗关闭，结束灵动岛实时预览")
        demoteAfterSettingsClosed()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindowController?.window
        else { return }
        AppLog.info("Settings", "设置窗 resignKey", [
            "appActive": NSApp.isActive,
            "visible": window.isVisible,
            "key": Self.describeKeyWindow()
        ])
        IslandController.shared?.setSettingsWindowFocused(false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindowController?.window
        else { return }
        AppLog.info("Settings", "设置窗 becomeKey", [
            "appActive": NSApp.isActive,
            "key": Self.describeKeyWindow()
        ])
        IslandController.shared?.setSettingsWindowFocused(true)
    }

    private static func describeKeyWindow() -> String {
        guard let key = NSApp.keyWindow else { return "nil" }
        let title = key.title.isEmpty ? String(describing: type(of: key)) : key.title
        return "\(title)#\(ObjectIdentifier(key))"
    }

    private func promoteForSettingsWindow() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        AppLog.debug("Settings", "activationPolicy → regular")
    }

    private func demoteAfterSettingsClosed() {
        // 下一轮 runloop 再降级，避免关窗动画期间抢焦点异常。
        DispatchQueue.main.async {
            guard !self.isSettingsPresented else { return }
            IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
            NSApp.setActivationPolicy(.accessory)
            AppLog.warn("Settings", "设置窗已关，activationPolicy → accessory")
        }
    }

    @objc private func quit() {
        AppLog.info("Overlay", "退出应用")
        NSApp.terminate(nil)
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let existing = settingsWindowController?.window {
            return existing
        }
        let window = makeSettingsWindow()
        settingsWindowController = NSWindowController(window: window)
        AppLog.info("Settings", "设置窗已创建", ["chrome": "whitePage-grayCards"])
        return window
    }

    private func prewarmSettingsWindowIfNeeded() {
        guard settingsWindowController?.window == nil else { return }
        let window = makeSettingsWindow()
        // 放到屏外并先 layout 一次，不抢焦点、不切 activationPolicy。
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderOut(nil)
        settingsWindowController = NSWindowController(window: window)
        AppLog.info("Settings", "设置窗已预热")
    }

    private func makeSettingsWindow() -> NSWindow {
        let root = SettingsRootView(settings: IslandSettings.shared)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = SettingsChrome.nsPageBackground.cgColor

        let size = SettingsChrome.windowDefaultSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Ridge"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SettingsChrome.nsPageBackground
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = SettingsChrome.windowMinSize
        window.setContentSize(size)
        window.delegate = self
        return window
    }

    /// 按当前侧栏页同步岛预览态（复用隐藏窗时 onAppear 不一定再跑）。
    private func syncIslandPreviewForCurrentSection() {
        switch SettingsNavigator.shared.section {
        case .island, .widgets, .general, .privacy, .about:
            ResourceMonitorSession.shared.setSettingsVisible(false)
            // 各设置页均用页内预览，打开时不钉住展开真岛。
            IslandController.shared?.beginSettingsSessionCollapsed()
        case .resourceMonitor, .focusInsights:
            ResourceMonitorSession.shared.setSettingsVisible(true)
            IslandController.shared?.beginSettingsSessionCollapsed()
        }
    }

    /// 钉死内容尺寸后，按「内容矩形 → 外框」居中到指定屏的 visibleFrame。
    private func applyDefaultSizeAndCenter(_ window: NSWindow, on screen: NSScreen?) {
        let contentSize = SettingsChrome.windowDefaultSize
        window.setContentSize(contentSize)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        center(window, contentSize: contentSize, on: screen)
    }

    private func center(_ window: NSWindow, contentSize: NSSize, on screen: NSScreen?) {
        guard let screen else {
            window.center()
            return
        }
        // 用 frameRect(forContentRect:) 拿含标题栏的外框，避免只按 content 宽算原点导致视觉偏一侧。
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - frameSize.width / 2,
            y: visible.midY - frameSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: frameSize), display: true)
    }

    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
