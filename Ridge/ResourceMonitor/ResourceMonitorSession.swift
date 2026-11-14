import AppKit
import Combine
import Foundation

/// 资源监控会话：轻量 2s（RAM/CPU）+ 重采样设置页 6s / 后台 15s（进程树），告警 / 杀进程 / purge。
@MainActor
final class ResourceMonitorSession: ObservableObject {
    static let shared = ResourceMonitorSession()

    @Published private(set) var snapshot = ResourceSnapshot()
    @Published private(set) var lastActionBanner: String?
    @Published private(set) var isPurging = false
    @Published var expandedAppID: String?
    /// 用户主动收起后，本轮设置会话内不再自动展开第一项。
    private var userCollapsedExpand = false
    /// 今日击键 / 切换（降低整页对 ActivityStore 的轮询）。
    @Published private(set) var todayKeystrokes = 0
    /// 今日击键峰值整点时段文案，如 `12:00–13:00`；尚无击键为 nil。
    @Published private(set) var keystrokePeakRangeText: String?
    @Published private(set) var todaySwitches = 0
    @Published private(set) var focusSlices: [ResourceFocusSlice] = []
    @Published private(set) var focusRanks: [ResourceFocusRank] = []
    /// 今日真实时序段（按切换交错着色；窗口=首次活动→现在）。
    @Published private(set) var focusTimeline: [ResourceFocusTimelineSegment] = []
    /// 时序带起点（今日首次前台）；无活动为 nil。
    @Published private(set) var focusTimelineAnchor: Date?
    /// 今日所有 App 驻留总秒。
    @Published private(set) var todayFocusTotalSeconds: TimeInterval = 0
    @Published private(set) var yearDays: [ResourceDayAggregate] = []
    /// 输入监控（击键）是否已授权。
    @Published private(set) var inputMonitoringGranted = false

    private let settings = ResourceMonitorSettings.shared
    private let activity = ResourceActivityStore.shared
    private var lightTimer: Timer?
    private var started = false
    private var previousCPU: ResourceSystemMetrics.CPUSample?
    private var alertArmed = true
    private var bannerTask: Task<Void, Never>?
    private var heavyTask: Task<Void, Never>?
    private var lastHeavyAt: Date = .distantPast
    private var settingsVisible = false
    private var tickGeneration = 0
    private var lastYearRefresh: Date = .distantPast
    /// 高压已触发但进程树尚未就绪，等重采样后再投递告警。
    private var awaitingTopForAlert = false
    private var keystrokeObserver: NSObjectProtocol?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        ResourceFocusTracker.shared.start()
        ResourceKeystrokeMonitor.shared.start()
        // 轻量指标不必 1s：2s 足够，减轻设置页重绘与主机负载。
        lightTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.lightTick()
            }
        }
        RunLoop.main.add(lightTimer!, forMode: .common)
        observeKeystrokePeakUpdates()
        refreshInputMonitoringStatus()
        lightTick()
        scheduleHeavy(force: true)
        AppLog.info("ResourceMonitor", "会话已启动")
    }

    func refreshInputMonitoringStatus() {
        let granted = ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
            || ResourceKeystrokeMonitor.shared.isListening
        if inputMonitoringGranted != granted {
            inputMonitoringGranted = granted
            AppLog.debug("ResourceMonitor", "输入监控状态", ["granted": granted])
        }
    }

    func requestInputMonitoring() {
        AppLog.info("ResourceMonitor", "设置页申请输入监控")
        let granted = ResourceKeystrokeMonitor.shared.requestInputMonitoringAccess()
        inputMonitoringGranted = granted || ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
        if inputMonitoringGranted {
            flashBanner(L10n.ResourceMonitor.permissionGrantedBanner)
        }
    }

    func stop() {
        lightTimer?.invalidate()
        lightTimer = nil
        heavyTask?.cancel()
        heavyTask = nil
        if let keystrokeObserver {
            NotificationCenter.default.removeObserver(keystrokeObserver)
            self.keystrokeObserver = nil
        }
        ResourceFocusTracker.shared.stop()
        ResourceKeystrokeMonitor.shared.stop()
        started = false
    }

    func setSettingsVisible(_ visible: Bool) {
        let wasVisible = settingsVisible
        settingsVisible = visible
        if visible {
            userCollapsedExpand = false
            ensureDefaultExpandedApp()
            AppLog.info("ResourceMonitor", "设置页可见", ["wasVisible": wasVisible])
            // 让设置页先完成首帧布局，再刷活动数据 / 进程树。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.settingsVisible else { return }
                self.refreshActivityUI()
                self.scheduleHeavy(force: true)
            }
        } else if wasVisible {
            // 离开页时取消在途重采样，避免切侧栏时主线程还在吃大图更新。
            heavyTask?.cancel()
            heavyTask = nil
            AppLog.info("ResourceMonitor", "设置页离开，已取消在途进程树采样")
        }
    }

    /// 轻量：只读 host 统计，避免主线程 `ps`。
    private func lightTick() {
        let mem = ResourceSystemMetrics.memory()
        let cpuNow = ResourceSystemMetrics.cpuSample()
        let cpuPercent: Double
        if let cpuNow {
            cpuPercent = ResourceSystemMetrics.cpuPercent(previous: previousCPU, current: cpuNow)
            previousCPU = cpuNow
        } else {
            cpuPercent = snapshot.cpuPercent
        }
        let ramPercent = mem.totalBytes > 0
            ? (Double(mem.usedBytes) / Double(mem.totalBytes)) * 100
            : 0
        let swapPercent = mem.swapTotalBytes > 0
            ? (Double(mem.swapUsedBytes) / Double(mem.swapTotalBytes)) * 100
            : 0

        var next = snapshot
        next.sampledAt = Date()
        next.ramUsedBytes = mem.usedBytes
        next.ramTotalBytes = mem.totalBytes
        next.ramPercent = ramPercent
        next.swapUsedBytes = mem.swapUsedBytes
        next.swapTotalBytes = mem.swapTotalBytes
        next.swapPercent = swapPercent
        next.cpuPercent = cpuPercent
        next.cpuCelsius = ResourceCPUTemperature.celsius()
        // topApps 由重采样更新；此处保留。
        if next != snapshot {
            snapshot = next
        }

        activity.noteRamSample(percent: ramPercent, usedBytes: mem.usedBytes)
        evaluateAlert()

        // 进程树 `ps` 更贵：设置页内 6s，后台 15s。
        let heavyInterval: TimeInterval = settingsVisible ? 6 : 15
        if Date().timeIntervalSince(lastHeavyAt) >= heavyInterval {
            scheduleHeavy(force: false)
        }
        if settingsVisible {
            refreshActivityUI()
            refreshInputMonitoringStatus()
        }
    }

    private func observeKeystrokePeakUpdates() {
        if keystrokeObserver != nil { return }
        keystrokeObserver = NotificationCenter.default.addObserver(
            forName: .ridgeResourceKeystrokesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActivityUI()
            }
        }
    }

    private func scheduleHeavy(force: Bool) {
        if !force, heavyTask != nil { return }
        heavyTask?.cancel()
        tickGeneration &+= 1
        let generation = tickGeneration
        lastHeavyAt = Date()
        // 主线程只取 App 列表；`ps` + 进程树聚合全在后台，避免切设置侧栏时卡死。
        let seeds = ResourceAppAggregator.runningAppSeeds()
        heavyTask = Task.detached(priority: .utility) {
            let load = ResourceAppAggregator.loadProcesses()
            guard !Task.isCancelled else { return }
            let top = ResourceAppAggregator.topApps(from: load.processes, seeds: seeds, limit: 5)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.tickGeneration == generation else { return }
                var next = self.snapshot
                next.topApps = ResourceAppAggregator.enrichChildTitles(top.apps)
                next.monitoredProcessCount = top.monitoredCount
                next.kernelProcessCount = load.kernelHostedCount
                if next != self.snapshot {
                    self.snapshot = next
                }
                // 默认展开占用第一的 App；无展开或原展开项已不在列表时回落到第一项。
                self.ensureDefaultExpandedApp()
                self.heavyTask = nil
                AppLog.debug("ResourceMonitor", "进程树已刷新", [
                    "apps": top.apps.count,
                    "monitored": top.monitoredCount,
                    "kernel": load.kernelHostedCount,
                    "settingsVisible": self.settingsVisible,
                    "expanded": self.expandedAppID ?? "",
                    "topChild": next.topApps.first?.children.first?.title ?? ""
                ])
                if self.awaitingTopForAlert {
                    self.evaluateAlert()
                }
            }
        }
    }

    private func refreshActivityUI() {
        let today = activity.todayAggregate()
        if todayKeystrokes != today.keystrokes { todayKeystrokes = today.keystrokes }
        if todaySwitches != today.appSwitches { todaySwitches = today.appSwitches }
        let peakText: String?
        if let peak = activity.peakKeystrokeHourRange() {
            peakText = String(format: "%02d:00–%02d:00", peak.startHour, peak.endHour)
        } else {
            peakText = nil
        }
        if peakText != keystrokePeakRangeText { keystrokePeakRangeText = peakText }

        let ranks = activity.todayFocusRanks(limit: 5)
        if ranks != focusRanks {
            focusRanks = ranks
            AppLog.debug("ResourceMonitor", "专注驻留排行已刷新", [
                "count": ranks.count,
                "top": ranks.first?.name ?? "",
                "topKeys": ranks.first?.keystrokes ?? 0
            ])
        }
        let slices = ranks.map {
            ResourceFocusSlice(
                bundleID: $0.bundleID,
                name: $0.name,
                seconds: $0.seconds,
                colorIndex: $0.colorIndex
            )
        }
        if slices != focusSlices { focusSlices = slices }
        let timeline = activity.todayFocusTimeline()
        if timeline != focusTimeline {
            focusTimeline = timeline
            AppLog.debug("ResourceMonitor", "专注时序带已刷新", ["segments": timeline.count])
        }
        let anchor = activity.todayFocusTimelineAnchor()
        if anchor != focusTimelineAnchor { focusTimelineAnchor = anchor }
        let totalFocus = activity.todayTotalFocusSeconds()
        if totalFocus != todayFocusTotalSeconds { todayFocusTotalSeconds = totalFocus }

        // 年热力含「今日」击键；设置页内与今日累计同频刷新，避免年累计落后一大截。
        let days = activity.yearAggregates()
        if days != yearDays { yearDays = days }
        lastYearRefresh = Date()
    }

    private func evaluateAlert() {
        let over = snapshot.ramPercent >= settings.ramThresholdPercent
        if !over {
            alertArmed = true
            awaitingTopForAlert = false
            return
        }
        guard settings.alertEnabled, !settings.isMuted else { return }
        // 已武装，或正在等进程树补齐后再投递。
        guard alertArmed || awaitingTopForAlert else { return }

        guard let top = snapshot.topApps.first else {
            if !awaitingTopForAlert {
                awaitingTopForAlert = true
                AppLog.info("ResourceMonitor", "RAM 高压待投递，先刷进程树", [
                    "percent": String(format: "%.1f", snapshot.ramPercent)
                ])
            }
            scheduleHeavy(force: true)
            return
        }

        alertArmed = false
        awaitingTopForAlert = false
        let notice = ResourceRAMPressureNotice(
            id: "ram-\(Int(Date().timeIntervalSince1970))",
            ramUsedBytes: snapshot.ramUsedBytes,
            ramPercent: snapshot.ramPercent,
            topAppName: top.name,
            topAppMemoryBytes: top.memoryBytes
        )
        IslandNoticeCenter.shared.present(.ramPressure(notice))
        AppLog.info("ResourceMonitor", "已投递 RAM 高压通知", [
            "percent": String(format: "%.1f", snapshot.ramPercent),
            "top": top.name,
            "topMB": Int(top.memoryBytes / (1024 * 1024))
        ])
    }

    /// 默认展开 Top1；用户收起后本会话不再强行展开。
    func ensureDefaultExpandedApp() {
        let apps = snapshot.topApps
        guard let first = apps.first, !first.children.isEmpty else { return }
        if let id = expandedAppID,
           apps.contains(where: { $0.id == id && !$0.children.isEmpty })
        {
            return
        }
        if expandedAppID == nil, userCollapsedExpand { return }
        expandedAppID = first.id
        AppLog.debug("ResourceMonitor", "默认展开 Top App", ["id": first.id, "name": first.name])
    }

    func toggleExpandedApp(_ appID: String) {
        if expandedAppID == appID {
            expandedAppID = nil
            userCollapsedExpand = true
        } else {
            expandedAppID = appID
            userCollapsedExpand = false
        }
    }

    func collapseExpandedHierarchy() {
        guard expandedAppID != nil else { return }
        expandedAppID = nil
        userCollapsedExpand = true
    }

    // MARK: - Actions

    func muteAlerts30m() {
        settings.muteAlerts(minutes: 30)
        flashBanner(L10n.ResourceMonitor.mutedBanner)
    }

    func setAlertEnabled(_ enabled: Bool) {
        settings.alertEnabled = enabled
    }

    @discardableResult
    func killApp(_ app: ResourceAppUsage) -> ResourceKillFailure? {
        AppLog.info("ResourceMonitor", "结束应用", [
            "name": app.name,
            "pid": app.mainPID,
            "children": app.children.count
        ])
        var lastError: ResourceKillFailure?
        let pids = [app.mainPID] + app.children.map(\.pid)
        for pid in Set(pids) {
            if let err = signalKill(pid: pid) {
                lastError = err
            }
        }
        if let lastError {
            flashBanner(lastError.message)
            AppLog.warn("ResourceMonitor", "结束应用部分失败", ["reason": lastError.message])
        } else {
            flashBanner(L10n.ResourceMonitor.killedBanner(app.name))
        }
        scheduleHeavy(force: true)
        return lastError
    }

    @discardableResult
    func killChild(_ child: ResourceChildProcess) -> ResourceKillFailure? {
        AppLog.info("ResourceMonitor", "结束子进程", ["pid": child.pid, "title": child.title])
        if let err = signalKill(pid: child.pid) {
            flashBanner(err.message)
            AppLog.warn("ResourceMonitor", "结束子进程失败", ["pid": child.pid, "reason": err.message])
            return err
        }
        flashBanner(L10n.ResourceMonitor.killedBanner(child.title))
        scheduleHeavy(force: true)
        return nil
    }

    func purgeMemory() {
        guard !isPurging else { return }
        isPurging = true
        flashBanner(L10n.ResourceMonitor.purging)
        AppLog.info("ResourceMonitor", "开始尽力回收内存")
        Task.detached(priority: .userInitiated) {
            let before = ResourceSystemMetrics.memory().usedBytes
            let result = ProjectShell.run("/usr/sbin/purge", arguments: [], timeout: 8)
            let after = ResourceSystemMetrics.memory().usedBytes
            let freed = before > after ? before - after : 0
            await MainActor.run {
                self.isPurging = false
                if result.exitCode == 0, freed > 0 {
                    self.flashBanner(L10n.ResourceMonitor.purgeDone(freed))
                } else if result.exitCode == 0 {
                    self.flashBanner(L10n.ResourceMonitor.purgeNoChange)
                } else {
                    self.flashBanner(L10n.ResourceMonitor.purgeFailed)
                }
                AppLog.info("ResourceMonitor", "回收内存结束", [
                    "code": result.exitCode,
                    "freed": freed
                ])
                self.lightTick()
            }
        }
    }

    private func signalKill(pid: Int32) -> ResourceKillFailure? {
        if kill(pid, 0) != 0 {
            let e = errno
            if e == ESRCH { return .notFound }
            if e == EPERM { return .permissionDenied }
            return .other(String(cString: strerror(e)))
        }
        if kill(pid, SIGTERM) == 0 { return nil }
        let e = errno
        if e == EPERM { return .protected }
        if e == ESRCH { return .notFound }
        if kill(pid, SIGKILL) == 0 { return nil }
        let e2 = errno
        if e2 == EPERM { return .protected }
        if e2 == ESRCH { return .notFound }
        return .other(String(cString: strerror(e2)))
    }

    private func flashBanner(_ text: String) {
        bannerTask?.cancel()
        lastActionBanner = text
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if lastActionBanner == text {
                lastActionBanner = nil
            }
        }
    }
}
