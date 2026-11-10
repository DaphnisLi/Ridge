import AppKit
import CoreGraphics
import Foundation

/// 监测前台原生全屏，以及系统 Apps / Siri 启动台遮罩（不依赖辅助功能权限）。
@MainActor
final class FullscreenMonitor {
    /// `fullscreen`：绿钮全屏 Space；`systemOverlay`：Apps / Siri 等系统遮罩（岛必须让路）。
    var onChange: ((_ fullscreen: Bool, _ systemOverlay: Bool) -> Void)?

    private(set) var isFullscreenActive = false
    private(set) var isSystemOverlayActive = false
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var debounceWork: DispatchWorkItem?

    private static let systemOverlayBundleIDs: Set<String> = [
        "com.apple.apps.launcher",
        "com.apple.Siri",
        "com.apple.launchpad.launcher"
    ]

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
            Task { @MainActor in self?.scheduleEvaluate(reason: "activate", delay: 0.15) }
        }
        observers = [space, activate]

        // 全屏 / Apps 进出有时不发 Space 通知，轮询兜底。
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate(reason: "poll") }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        evaluate(reason: "start")
        AppLog.info("Overlay", "全屏/系统遮罩监测已启动")
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
        let fullscreen = Self.detectFrontmostFullscreen()
        let overlay = Self.detectSystemOverlay()
        guard fullscreen != isFullscreenActive || overlay != isSystemOverlayActive else { return }
        isFullscreenActive = fullscreen
        isSystemOverlayActive = overlay
        let frontName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        AppLog.warn("Overlay", "桌面遮罩状态变化", [
            "fullscreen": fullscreen,
            "systemOverlay": overlay,
            "reason": reason,
            "app": frontName,
            "bundle": frontID
        ])
        onChange?(fullscreen, overlay)
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

                let fillsWidth = width >= screenW - 4
                let fillsHeight = height >= screenH - 4
                if fillsWidth && fillsHeight {
                    return true
                }

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

    /// Dock「App」启动台：经 Siri / Apps.launcher 铺大遮罩；Ridge 层级更高时会盖住导致「打不开」。
    private static func detectSystemOverlay() -> Bool {
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           systemOverlayBundleIDs.contains(id) {
            return true
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
                let owner = info[kCGWindowOwnerName as String] as? String ?? ""
                let bundleHint = info["kCGWindowOwnerPID"] // only name is reliable here
                _ = bundleHint
                let isSystemChrome = owner == "Siri"
                    || owner == "Apps"
                    || owner == "Launchpad"
                guard isSystemChrome else { continue }

                let layer = info[kCGWindowLayer as String] as? Int ?? 0
                // Apps 走 Siri 时 layer≈23；须高于普通窗。
                guard layer >= 20 else { continue }

                let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1
                guard alpha > 0.05 else { continue }

                guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
                else { continue }
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                // 启动台首帧接近全屏，随后可能收到中间态大面板。
                let coversMost =
                    width >= screenW * 0.55
                    && height >= screenH * 0.55
                if coversMost {
                    return true
                }
            }
        }
        return false
    }
}
