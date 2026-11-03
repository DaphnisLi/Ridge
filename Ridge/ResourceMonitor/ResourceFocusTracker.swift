import AppKit
import Foundation

/// 前台 App 切换 / 驻留。
@MainActor
final class ResourceFocusTracker {
    static let shared = ResourceFocusTracker()

    private var observer: NSObjectProtocol?
    private var tickTimer: Timer?

    private init() {}

    func start() {
        guard observer == nil else { return }
        // 启动只开始计时，不记一次「切换」。
        noteFrontmost(countSwitch: false)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.noteFrontmost()
            }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                ResourceActivityStore.shared.tickFocus()
                self?.noteFrontmost(countSwitch: false)
            }
        }
        AppLog.info("ResourceMonitor", "焦点跟踪已启动")
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func noteFrontmost(countSwitch: Bool = true) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        // Ridge 自身前台：不打断上一 App 时序（否则看设置页会大片留白，被误认为「没在用 App」）。
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        guard let bid = app.bundleIdentifier, !bid.isEmpty else { return }
        let name = app.localizedName ?? bid
        if countSwitch {
            ResourceActivityStore.shared.noteAppSwitch(bundleID: bid, name: name)
        } else {
            ResourceActivityStore.shared.ensureFocus(bundleID: bid, name: name)
        }
    }
}
