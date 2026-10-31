import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private weak var island: IslandController?
    private var settingsWindowController: NSWindowController?

    func start(island: IslandController) {
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
        AppLog.info("Overlay", "菜单栏已就绪")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settings = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 Ridge",
            action: #selector(quit),
            keyEquivalent: "q"
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
            return
        }

        let root = SettingsRootView(settings: IslandSettings.shared)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ridge"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .white
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        window.setContentSize(NSSize(width: 920, height: 620))
        window.delegate = self
        center(window, on: Self.activeScreen())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController = NSWindowController(window: window)
        AppLog.info("Settings", "设置窗已显示，已允许 ⌘Tab 切换")
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === settingsWindowController?.window
        else { return }
        demoteAfterSettingsClosed()
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
