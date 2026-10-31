import AppKit
import CoreGraphics
import Foundation

/// 监测前台是否处于原生全屏 Space（绿钮全屏；不依赖辅助功能权限）。
@MainActor
final class FullscreenMonitor {
    var onChange: ((Bool) -> Void)?

    private(set) var isFullscreenActive = false
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var debounceWork: DispatchWorkItem?

    func start() {
        stop()
        let nc = NSWorkspace.shared.notificationCenter
        let space = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleEvaluate(reason: "space", delay: 0.25) }
        }
        let activate = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleEvaluate(reason: "activate", delay: 0.2) }
        }
        observers = [space, activate]

        // 全屏进出有时不发 Space 通知，轮询兜底。
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate(reason: "poll") }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        evaluate(reason: "start")
        AppLog.info("Overlay", "全屏监测已启动")
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        debounceWork?.cancel()
        debounceWork = nil
    }

    /// 立即按当前前台状态重算（设置开关变化时调用）。
    func refresh(reason: String) {
        evaluate(reason: reason)
    }

    private func scheduleEvaluate(reason: String, delay: TimeInterval) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.evaluate(reason: reason) }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluate(reason: String) {
        let detected = Self.detectFrontmostFullscreen()
        guard detected != isFullscreenActive else { return }
        isFullscreenActive = detected
        let frontName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        AppLog.info("Overlay", "全屏状态变化", [
            "fullscreen": detected,
            "reason": reason,
            "app": frontName
        ])
        onChange?(detected)
    }

    /// 前台 App 是否有窗口铺满某块屏（约等于绿钮原生全屏）。
    private static func detectFrontmostFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let frontPID = front.processIdentifier

        if front.bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for screen in NSScreen.screens {
            let screenW = screen.frame.width
            let screenH = screen.frame.height
            guard screenW > 0, screenH > 0 else { continue }

            for info in infoList {
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID == frontPID
                else { continue }

                let layer = info[kCGWindowLayer as String] as? Int ?? 0
                // 普通窗与全屏内容层一般为 0。
                guard layer == 0 else { continue }

                let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1
                guard alpha > 0.05 else { continue }

                guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
                else { continue }

                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0

                // 铺满整块屏（允许少量误差）；比「必须贴顶 + 有标题」宽松得多。
                let fillsWidth = width >= screenW - 4
                let fillsHeight = height >= screenH - 4
                if fillsWidth && fillsHeight {
                    return true
                }

                // 部分 App 全屏高度略小于 screen.frame（仍远大于可见桌面高度）。
                let coversMost =
                    width >= screenW * 0.98
                    && height >= screenH * 0.96
                if coversMost {
                    return true
                }
            }
        }
        return false
    }
}
