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

        AppLog.info("Overlay", "菜单栏已就绪")
    }

    func stop() {
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
            title: "设置",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 Ridge",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func openSettings() {
        AppLog.info("Settings", "打开设置窗")
        // 设置打开期间进入 regular，才能被 ⌘Tab 切回来；关闭后再变回 accessory。
        promoteForSettingsWindow()

        if let existing = settingsWindowController?.window, existing.isVisible {
            center(existing, on: Self.activeScreen())
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            IslandController.shared?.beginSettingsSession()
            return
        }

        // 关窗后再开：销毁旧窗，避免残留白底/旧布局。
        if let stale = settingsWindowController?.window {
            stale.delegate = nil
            stale.close()
            settingsWindowController = nil
        }

        let root = SettingsRootView(settings: IslandSettings.shared)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = SettingsChrome.nsPageBackground.cgColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ridge"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SettingsChrome.nsPageBackground
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        window.setContentSize(NSSize(width: 920, height: 620))
        window.delegate = self
        center(window, on: Self.activeScreen())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController = NSWindowController(window: window)
        IslandController.shared?.beginSettingsSession()
        AppLog.info("Settings", "设置窗已显示", ["chrome": "whitePage-grayCards"])
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === settingsWindowController?.window
        else { return }
        // 关窗时 SwiftUI onDisappear 不一定触发；强制结束预览并收起岛。
        WidgetFlyAnimator.shared.cancel()
        IslandController.shared?.setSettingsLivePreview(false, forceCollapseOnEnd: true)
        AppLog.info("Settings", "设置窗关闭，结束灵动岛实时预览")
        demoteAfterSettingsClosed()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindowController?.window
        else { return }
        // 失焦：岛恢复正常悬停，不再钉住。
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
