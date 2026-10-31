import AppKit
import Foundation

/// 监听屏幕参数变化，重新解析刘海屏。
@MainActor
final class DisplayMonitor {
    var onScreensChanged: (() -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLog.info("Notch", "屏幕参数变化")
            Task { @MainActor in self?.onScreensChanged?() }
        }
        AppLog.debug("Notch", "屏幕监测已启动", ["screens": NSScreen.screens.count])
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
