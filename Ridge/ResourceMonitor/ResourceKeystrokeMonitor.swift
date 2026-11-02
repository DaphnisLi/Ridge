import AppKit
import CoreGraphics
import Foundation

/// 全局击键计数。无输入监控权限时静默失败；设置页可申请授权。
final class ResourceKeystrokeMonitor: @unchecked Sendable {
    static let shared = ResourceKeystrokeMonitor()

    private(set) var isListening = false
    private var port: CFMachPort?
    private let lock = NSLock()
    private var pending = 0
    private var flushTimer: Timer?

    private init() {}

    /// 是否已具备输入监控权限（与 tap 是否跑着可能短暂不一致）。
    var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    /// 弹系统授权；已拒绝则打开「隐私与安全性 → 输入监控」。
    @MainActor
    @discardableResult
    func requestInputMonitoringAccess() -> Bool {
        if CGPreflightListenEventAccess() {
            AppLog.info("ResourceMonitor", "输入监控已授权")
            start()
            return true
        }
        AppLog.info("ResourceMonitor", "请求输入监控权限")
        NSApp.activate(ignoringOtherApps: true)
        let granted = CGRequestListenEventAccess()
        AppLog.info("ResourceMonitor", "输入监控授权结果", ["granted": granted])
        if granted {
            start()
            return true
        }
        openInputMonitoringSettings()
        return false
    }

    @MainActor
    func openInputMonitoringSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                AppLog.info("ResourceMonitor", "已打开输入监控隐私设置", ["url": raw])
                return
            }
        }
        AppLog.warn("ResourceMonitor", "无法打开输入监控隐私设置")
    }

    @MainActor
    func start() {
        guard !isListening else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .keyDown, let refcon {
                    let monitor = Unmanaged<ResourceKeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    monitor.lock.lock()
                    monitor.pending += 1
                    monitor.lock.unlock()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            AppLog.warn("ResourceMonitor", "击键监听未启动（可能缺输入监控权限）")
            isListening = false
            return
        }
        port = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
        flushTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.flushToStore()
        }
        AppLog.info("ResourceMonitor", "击键监听已启动")
    }

    @MainActor
    func stop() {
        flushToStore()
        flushTimer?.invalidate()
        flushTimer = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        port = nil
        isListening = false
    }

    private func flushToStore() {
        lock.lock()
        let n = pending
        pending = 0
        lock.unlock()
        guard n > 0 else { return }
        Task { @MainActor in
            ResourceActivityStore.shared.addKeystrokes(n)
        }
    }
}
