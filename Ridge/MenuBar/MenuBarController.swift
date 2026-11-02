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

    /// 当前设置窗（可见时）。
    var settingsWindow: NSWindow? {
        let window = settingsWindowController?.window
        guard let window, window.isVisible else { return nil }
        return window
    }

    func start(island: IslandController) {
        Self.shared = self
        self.island = island
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Ridge"
            )
            button.image?.isTemplate = true
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

        let quit = NSMenuItem(
            title: L10n.Common.quitApp,
            action: #selector(quit),
            keyEquivalent: ""
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func openSettings() {
        let openedAt = Date()
        AppLog.info("Settings", "打开设置窗")
        // 设置打开期间进入 regular，才能被 ⌘Tab 切回来；关闭后再变回 accessory。
        promoteForSettingsWindow()

        let window = ensureSettingsWindow()
        center(window, on: Self.activeScreen())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 先把窗画出来，下一拍再钉岛，避免「建窗 + 展开岛」同帧抢主线程。
        DispatchQueue.main.async {
            self.syncIslandPreviewForCurrentSection()
            AppLog.info("Settings", "设置窗已前置", [
                "ms": Int(Date().timeIntervalSince(openedAt) * 1000),
                "section": SettingsNavigator.shared.section.rawValue,
                "reused": true
            ])
        }
    }

    /// 隐藏关闭：保留 hosting，下次打开不再冷启动 SwiftUI。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === settingsWindowController?.window else { return true }
        WidgetFlyAnimator.shared.cancel()
        ResourceMonitorSession.shared.setSettingsVisible(false)
        IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
        sender.orderOut(nil)
        AppLog.info("Settings", "设置窗已隐藏（保留实例）")
        demoteAfterSettingsClosed()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === settingsWindowController?.window
        else { return }
        WidgetFlyAnimator.shared.cancel()
        IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
        AppLog.info("Settings", "设置窗关闭，结束灵动岛实时预览")
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
            guard self.settingsWindowController?.window?.isVisible != true else { return }
            IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
            NSApp.setActivationPolicy(.accessory)
            AppLog.info("Settings", "设置窗已关，activationPolicy → accessory")
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Ridge"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SettingsChrome.nsPageBackground
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        window.setContentSize(NSSize(width: 920, height: 620))
        window.delegate = self
        return window
    }

    /// 按当前侧栏页同步岛预览态（复用隐藏窗时 onAppear 不一定再跑）。
    private func syncIslandPreviewForCurrentSection() {
        switch SettingsNavigator.shared.section {
        case .island:
            ResourceMonitorSession.shared.setSettingsVisible(false)
            IslandController.shared?.beginSettingsSession()
        case .controlDeck, .widgets:
            ResourceMonitorSession.shared.setSettingsVisible(false)
            IslandController.shared?.beginSettingsSessionCollapsed()
        case .resourceMonitor:
            ResourceMonitorSession.shared.setSettingsVisible(true)
            IslandController.shared?.beginSettingsSessionCollapsed()
        }
    }

    private func center(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
