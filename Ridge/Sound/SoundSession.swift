import AppKit
import Combine
import CoreAudio
import CoreGraphics
import Foundation

/// 声音中枢：输出设备、主音量、按 App 输出音量（Process Tap）。
@MainActor
final class SoundSession: ObservableObject {
    static let shared = SoundSession()

    @Published private(set) var outputDevices: [SoundOutputDevice] = []
    @Published private(set) var masterVolume: Double = 0.7
    @Published private(set) var apps: [SoundAppRow] = []
    @Published private(set) var tapAvailability: SoundTapAvailability = .available
    @Published private(set) var lastError: String?

    private let settings = SoundSettings.shared
    private var routes: [String: AnyObject] = [:]
    private var lingerUntil: [String: Date] = [:]
    private var pollTimer: Timer?
    private var hardwareListeners: [AudioObjectPropertyListenerBlock] = []
    private var hardwareRefreshWorkItem: DispatchWorkItem?
    private var started = false

    private let lingerSeconds: TimeInterval = 5
    /// HAL 插拔蓝牙时会连发 Devices 变更，中间态常缺设备；合并后再读。
    private let hardwareDebounceSeconds: TimeInterval = 0.25

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        if #available(macOS 14.2, *) {
            SoundAppVolumeRoute.cleanupOrphans()
        }
        refreshTapAvailability()
        refreshAll(reason: "start")
        installHardwareListeners()
        startPolling()
        AppLog.info("Sound", "声音会话已启动", [
            "tap": "\(tapAvailability)",
            "outputs": outputDevices.count
        ])
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        removeHardwareListeners()
        stopAllRoutes()
        started = false
        AppLog.info("Sound", "声音会话已停止")
    }

    private func stopAllRoutes() {
        if #available(macOS 14.2, *) {
            for case let route as SoundAppVolumeRoute in routes.values {
                route.stop()
            }
        }
        routes.removeAll()
    }

    // MARK: - Public actions

    func setMasterVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        masterVolume = clamped
        let ok = SoundDeviceService.setMasterOutputVolume(clamped)
        if !ok {
            AppLog.warn("Sound", "写入系统主音量失败", ["volume": clamped])
        }
    }

    func selectOutput(uid: String) {
        guard SoundDeviceService.setDefaultOutput(uid: uid) else {
            AppLog.warn("Sound", "切换默认输出失败", ["uid": uid])
            return
        }
        AppLog.info("Sound", "已切换默认输出", ["uid": uid])
        refreshDevices(reason: "selectOutput")
        rebindRoutesToDefaultOutput()
    }

    func setAppVolume(_ value: Double, for key: String) {
        settings.setVolume(value, for: key)
        applyRoute(for: key)
        refreshApps(reason: "setVolume")
    }

    func setAppMuted(_ muted: Bool, for key: String) {
        settings.setMuted(muted, for: key)
        if #available(macOS 14.2, *), let route = routes[key] as? SoundAppVolumeRoute {
            route.isMuted = muted
        } else {
            applyRoute(for: key)
        }
        refreshApps(reason: "setMuted")
    }

    func requestScreenCaptureAccess() {
        let granted = CGRequestScreenCaptureAccess()
        AppLog.info("Sound", "请求屏幕录制权限（Process Tap）", ["granted": granted])
        refreshTapAvailability()
        refreshApps(reason: "screenCapture")
    }

    func resetAppVolumes() {
        stopAllRoutes()
        settings.resetAllAppVolumes()
        refreshApps(reason: "reset")
    }

    // MARK: - Refresh

    private func refreshAll(reason: String) {
        refreshDevices(reason: reason)
        refreshApps(reason: reason)
    }

    private func refreshDevices(reason: String) {
        let previous = outputDevices.map(\.uid)
        let next = SoundDeviceService.outputDevices()
        // 硬件抖动时偶发读到空/残缺列表：若默认设备仍在且结果明显变少，保留上一帧。
        if shouldKeepPreviousOutputs(previous: outputDevices, next: next, reason: reason) {
            AppLog.debug("Sound", "忽略残缺设备枚举", [
                "reason": reason,
                "previous": previous.count,
                "next": next.count
            ])
            masterVolume = SoundDeviceService.masterOutputVolume()
            return
        }
        let previousBatteries = outputDevices.map(\.batteryPercent)
        outputDevices = next
        masterVolume = SoundDeviceService.masterOutputVolume()
        let names = outputDevices.map(\.name).joined(separator: " | ")
        let batteries = outputDevices.compactMap(\.batteryPercent)
        let uidChanged = previous != outputDevices.map(\.uid)
        let batteryChanged = previousBatteries != outputDevices.map(\.batteryPercent)
        let changed = uidChanged || batteryChanged
        if changed || reason == "start" || reason == "selectOutput" {
            AppLog.info("Sound", "刷新设备完成", [
                "reason": reason,
                "outputs": outputDevices.count,
                "outputNames": names,
                "batteries": batteries.map(String.init).joined(separator: ","),
                "master": String(format: "%.2f", masterVolume),
                "changed": changed
            ])
        }
    }

    /// 连接 AirPods 等时 HAL 会短暂少报设备；避免 UI 闪回「只有电脑」。
    private func shouldKeepPreviousOutputs(
        previous: [SoundOutputDevice],
        next: [SoundOutputDevice],
        reason: String
    ) -> Bool {
        guard reason == "hardware" || reason == "poll" || reason == "hardwareDebounced" else {
            return false
        }
        guard !previous.isEmpty, next.count < previous.count else { return false }
        // 若上一帧的默认设备仍是系统默认，但本帧列表里找不到它 → 残缺读取。
        guard let previousDefault = previous.first(where: \.isDefault) else { return false }
        let systemDefault = SoundDeviceService.defaultOutputDeviceID()
        let systemStillPrevious = systemDefault.map { $0 == previousDefault.objectID } ?? false
        let nextHasPreviousDefault = next.contains(where: { $0.uid == previousDefault.uid })
        return systemStillPrevious && !nextHasPreviousDefault
    }

    private func scheduleHardwareRefresh() {
        hardwareRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshAll(reason: "hardwareDebounced")
            }
        }
        hardwareRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hardwareDebounceSeconds, execute: item)
    }

    private func refreshApps(reason: String) {
        let now = Date()
        lingerUntil = lingerUntil.filter { $0.value > now }

        let live = SoundProcessMonitor.snapshot()
        for process in live where process.isRunningOutput {
            let key = process.bundleID ?? "pid:\(process.pid)"
            lingerUntil[key] = now.addingTimeInterval(lingerSeconds)
        }

        let lingerKeys = Set(lingerUntil.keys)
        let controlled = Set(routes.keys)
        apps = SoundProcessMonitor.aggregatedRows(
            volumes: settings.appVolumes,
            muted: settings.appMuted,
            lingerKeys: lingerKeys,
            controlledKeys: controlled
        )

        // 清理已退出且无偏好的路由。
        let aliveKeys = Set(apps.map(\.key))
        for key in routes.keys where !aliveKeys.contains(key) {
            if #available(macOS 14.2, *), let route = routes[key] as? SoundAppVolumeRoute {
                route.stop()
            }
            routes.removeValue(forKey: key)
            AppLog.debug("Sound", "停止已退出 App 路由", ["key": key, "reason": reason])
        }

        // 对有偏好且正在播放的 App 确保路由。
        for row in apps where row.isPlaying {
            let needsControl = row.volume < 0.999 || row.isMuted
            if needsControl {
                applyRoute(for: row.key)
            } else if routes[row.key] != nil {
                if #available(macOS 14.2, *), let route = routes[row.key] as? SoundAppVolumeRoute {
                    route.stop()
                }
                routes.removeValue(forKey: row.key)
            }
        }

        // 同步 controlled 标记。
        if Set(routes.keys) != controlled {
            apps = SoundProcessMonitor.aggregatedRows(
                volumes: settings.appVolumes,
                muted: settings.appMuted,
                lingerKeys: lingerKeys,
                controlledKeys: Set(routes.keys)
            )
        }
    }

    private func applyRoute(for key: String) {
        refreshTapAvailability()
        guard tapAvailability == .available else {
            lastError = L10n.Sound.tapUnavailableHint
            return
        }

        let volume = settings.volume(for: key)
        let muted = settings.isMuted(for: key)
        let needs = volume < 0.999 || muted
        guard needs else {
            if #available(macOS 14.2, *), let route = routes.removeValue(forKey: key) as? SoundAppVolumeRoute {
                route.stop()
                AppLog.info("Sound", "恢复 App 直通（音量 100%）", ["key": key])
            } else {
                routes.removeValue(forKey: key)
            }
            return
        }

        guard #available(macOS 14.2, *) else { return }

        let processes = SoundProcessMonitor.snapshot().filter {
            ($0.bundleID ?? "pid:\($0.pid)") == key && $0.isRunningOutput
        }
        let objectIDs = processes.map(\.objectID)
        guard !objectIDs.isEmpty else { return }
        guard let outputUID = outputDevices.first(where: \.isDefault)?.uid
                ?? SoundDeviceService.outputDevices().first(where: \.isDefault)?.uid
        else {
            AppLog.debug("Sound", "无默认输出，跳过 App 路由", ["key": key])
            return
        }

        do {
            if let existing = routes[key] as? SoundAppVolumeRoute {
                try existing.updateProcesses(objectIDs)
                try existing.updateOutputUID(outputUID)
                existing.volume = Float(volume)
                existing.isMuted = muted
            } else {
                let route = SoundAppVolumeRoute(
                    key: key,
                    processObjectIDs: objectIDs,
                    outputDeviceUID: outputUID
                )
                route.volume = Float(volume)
                route.isMuted = muted
                try route.start()
                routes[key] = route
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            AppLog.error("Sound", "App 音量路由失败，已 fail-open", [
                "key": key,
                "error": error.localizedDescription
            ])
            (routes[key] as? SoundAppVolumeRoute)?.stop()
            routes.removeValue(forKey: key)
        }
    }

    private func rebindRoutesToDefaultOutput() {
        guard #available(macOS 14.2, *) else { return }
        guard let uid = outputDevices.first(where: \.isDefault)?.uid else { return }
        for (key, value) in routes {
            guard let route = value as? SoundAppVolumeRoute else { continue }
            do {
                try route.updateOutputUID(uid)
            } catch {
                AppLog.warn("Sound", "切换输出后重建路由失败", [
                    "key": key,
                    "error": error.localizedDescription
                ])
                route.stop()
                routes.removeValue(forKey: key)
                applyRoute(for: key)
            }
        }
    }

    private func refreshTapAvailability() {
        if #unavailable(macOS 14.2) {
            tapAvailability = .needsMacOS142
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            tapAvailability = .needsScreenCapture
            return
        }
        tapAvailability = .available
    }

    // MARK: - Polling / listeners

    private func startPolling() {
        pollTimer?.invalidate()
        // HAL 对 IsRunningOutput 监听不可靠，1s 轮询兜底。
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // 插拔耳机常只改 DataSource，不一定触发 Devices 监听；轮询刷新输出列表。
                self?.refreshDevices(reason: "poll")
                self?.refreshApps(reason: "poll")
            }
        }
    }

    private func installHardwareListeners() {
        removeHardwareListeners()
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyProcessObjectList
        ]
        for selector in selectors {
            if let block = CoreAudioProperty.addListener(object: .system, selector, block: { [weak self] in
                Task { @MainActor in
                    self?.scheduleHardwareRefresh()
                }
            }) {
                hardwareListeners.append(block)
            }
        }
    }

    private func removeHardwareListeners() {
        // AudioObjectRemovePropertyListenerBlock 需要原 block；简化：进程退出时 HAL 会清。
        hardwareListeners.removeAll()
    }
}
