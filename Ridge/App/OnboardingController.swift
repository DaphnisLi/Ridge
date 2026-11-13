import AppKit
import SwiftUI

/// 首次启动轻量引导。
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var windowController: NSWindowController?

    func presentIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: AppIdentity.onboardingCompletedKey) else { return }
        present()
    }

    func present() {
        if windowController?.window?.isVisible == true {
            windowController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        let root = OnboardingView(
            onFinish: { [weak self] enableLogin in
                if enableLogin {
                    _ = LoginItemService.shared.setEnabled(true)
                }
                UserDefaults.standard.set(true, forKey: AppIdentity.onboardingCompletedKey)
                AppLog.warn("Onboarding", "引导已完成", ["loginItem": enableLogin])
                self?.close()
            },
            onSkip: { [weak self] in
                UserDefaults.standard.set(true, forKey: AppIdentity.onboardingCompletedKey)
                AppLog.warn("Onboarding", "引导已跳过")
                self?.close()
            }
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.Onboarding.windowTitle
        window.titlebarAppearsTransparent = true
        window.contentViewController = hosting
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false
        let wc = NSWindowController(window: window)
        windowController = wc
        NSApp.setActivationPolicy(.regular)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.warn("Onboarding", "引导窗已显示")
    }

    private func close() {
        windowController?.close()
        windowController = nil
        DispatchQueue.main.async {
            if MenuBarController.shared?.isSettingsPresented != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: AppIdentity.onboardingCompletedKey) {
            UserDefaults.standard.set(true, forKey: AppIdentity.onboardingCompletedKey)
            AppLog.warn("Onboarding", "引导窗关闭，视为跳过")
        }
        windowController = nil
        DispatchQueue.main.async {
            if MenuBarController.shared?.isSettingsPresented != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

struct OnboardingView: View {
    var onFinish: (_ enableLoginAtLogin: Bool) -> Void
    var onSkip: () -> Void

    @State private var page = 0
    @State private var enableLogin = true

    private let pageCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch page {
                case 0:
                    step(title: L10n.Onboarding.stepIslandTitle, bodyText: L10n.Onboarding.stepIslandBody)
                case 1:
                    step(title: L10n.Onboarding.stepPermissionsTitle, bodyText: L10n.Onboarding.stepPermissionsBody)
                case 2:
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.Onboarding.stepLaunchTitle)
                            .font(SettingsChrome.Font.pageTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Onboarding.stepLaunchBody)
                            .font(SettingsChrome.Font.body)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        Toggle(isOn: $enableLogin) {
                            Text(L10n.General.launchAtLogin)
                                .font(SettingsChrome.Font.rowTitle)
                        }
                        .toggleStyle(.switch)
                        Spacer(minLength: 0)
                    }
                default:
                    step(title: L10n.Onboarding.stepWidgetsTitle, bodyText: L10n.Onboarding.stepWidgetsBody)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Button(L10n.Onboarding.skip) { onSkip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .font(SettingsChrome.Font.body)
                Spacer()
                Text("\(page + 1) / \(pageCount)")
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer()
                if page < pageCount - 1 {
                    Button(L10n.Onboarding.next) { page += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.Onboarding.done) {
                        onFinish(enableLogin)
                        SettingsNavigator.shared.open(.widgets)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
        .background(SettingsChrome.pageBackground)
        .preferredColorScheme(.light)
    }

    private func step(title: String, bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(bodyText)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            Spacer(minLength: 0)
        }
    }
}
