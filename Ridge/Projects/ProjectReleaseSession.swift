import AppKit
import Combine
import Darwin
import Foundation

/// 跨线程取消监视等待（kqueue 轮询检查）。
private final class WatchCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }
}

/// 项目释放中枢：扫描、聚合、一键释放、Watch 结束通知。
@MainActor
final class ProjectReleaseSession: ObservableObject {
    static let shared = ProjectReleaseSession()

    @Published private(set) var projects: [ScannedProject] = []
    @Published private(set) var groups: [ProjectRuntimeGroup] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var watches: [ProjectWatchTarget] = []
    /// 监视结束：控制台 Watch 区短展示；岛上由 `IslandNoticeCenter` → `system.islandNotice`。
    @Published private(set) var lastWatchEnded: ProjectWatchEndedNotice?

    private let settings = ProjectSettings.shared
    private var pollTimer: Timer?
    private var watchTimer: Timer?
    private struct ExitMonitor {
        let task: Task<Void, Never>
        let cancel: WatchCancelFlag
    }

    private var exitMonitors: [Int32: ExitMonitor] = [:]
    private var started = false
    private var releasingIDs = Set<String>() {
        didSet { objectWillChange.send() }
    }
    /// 最近一次释放结果（岛上短提示）。
    @Published private(set) var lastActionBanner: String?
    /// 目录扫描比进程采样贵；轮询时复用结果，约 45s 再扫一遍。
    private var lastCatalogScanAt = Date.distantPast
    private let catalogRescanInterval: TimeInterval = 45
    /// 刷新进行中时，把后续请求压成一次；释放后刷新优先级最高。
    private var pendingRefreshReason: String?

    private init() {}

    func start() {
        guard !started else {
            refresh(reason: "alreadyStarted")
            return
        }
        started = true
        refresh(reason: "start")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "poll")
            }
        }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkWatches()
            }
        }
        AppLog.info("Projects", "项目释放会话已启动")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        watchTimer?.invalidate()
        watchTimer = nil
        for monitor in exitMonitors.values {
            monitor.cancel.cancelled = true
            monitor.task.cancel()
        }
        exitMonitors.removeAll()
        pendingRefreshReason = nil
        started = false
        AppLog.info("Projects", "项目释放会话已停止")
    }

    func refresh(reason: String) {
        if isRefreshing {
            // 释放后采样不可丢；与进行中的 poll 冲突时排队，结束后立刻再采。
            if reason == "afterRelease" || pendingRefreshReason != "afterRelease" {
                pendingRefreshReason = reason
            }
            AppLog.debug("Projects", "刷新进行中，已排队", [
                "incoming": reason,
                "pending": pendingRefreshReason ?? "nil"
            ])
            return
        }
        isRefreshing = true
        let roots = settings.roots
        let cachedProjects = projects
        // 仅启动 / 改根目录 / 空缓存 / 到期轮询才重扫目录；释放后只重采进程，避免数秒卡顿。
        let forceCatalog =
            reason == "start"
            || reason == "rootsChanged"
            || reason == "alreadyStarted"
        let shouldRescanCatalog =
            forceCatalog
            || cachedProjects.isEmpty
            || (reason == "poll" && Date().timeIntervalSince(lastCatalogScanAt) >= catalogRescanInterval)
        let samplePriority: TaskPriority = reason == "afterRelease" ? .userInitiated : .utility
        AppLog.debug("Projects", "开始刷新", [
            "reason": reason,
            "catalogRescan": shouldRescanCatalog
        ])
        Task.detached(priority: samplePriority) {
            let scanStarted = Date()
            let scanned = shouldRescanCatalog
                ? ProjectCatalog.scan(roots: roots)
                : cachedProjects
            let catalogMs = Int(Date().timeIntervalSince(scanStarted) * 1000)
            let sampleStarted = Date()
            let sampled = ProjectRuntimeSampler.sample(projects: scanned, roots: roots)
            let sampleMs = Int(Date().timeIntervalSince(sampleStarted) * 1000)
            await MainActor.run {
                if shouldRescanCatalog {
                    self.projects = scanned
                    self.lastCatalogScanAt = Date()
                    AppLog.debug("Projects", "已重扫项目目录", [
                        "reason": reason,
                        "projects": scanned.count,
                        "ms": catalogMs
                    ])
                }
                self.groups = sampled
                self.refreshWatchMemory(from: sampled)
                self.isRefreshing = false
                self.lastError = nil
                if reason != "poll" {
                    let attributed = sampled.filter { $0.project != nil }
                    AppLog.info("Projects", "刷新完成", [
                        "reason": reason,
                        "projects": scanned.count,
                        "projectNames": scanned.prefix(8).map(\.name).joined(separator: ","),
                        "groups": sampled.count,
                        "attributed": attributed.count,
                        "attributedNames": attributed.prefix(8).compactMap(\.project?.name).joined(separator: ","),
                        "items": sampled.reduce(0) { $0 + $1.items.count },
                        "catalogRescan": shouldRescanCatalog,
                        "catalogMs": catalogMs,
                        "sampleMs": sampleMs,
                        "roots": roots.joined(separator: ",")
                    ])
                }
                if let pending = self.pendingRefreshReason {
                    self.pendingRefreshReason = nil
                    self.refresh(reason: pending)
                }
            }
        }
    }

    func release(group: ProjectRuntimeGroup) {
        guard group.canRelease else {
            AppLog.warn("Projects", "释放跳过：不可释放", ["group": group.id])
            return
        }
        let key = group.id
        guard !releasingIDs.contains(key) else { return }
        releasingIDs.insert(key)

        let killable = group.items.filter(\.canRelease)
        let pids = Array(Set(killable.compactMap(\.pid)))
        let containers = Array(Set(killable.compactMap(\.containerID)))
        let projectName = group.project?.name ?? L10n.Projects.unattributed
        let docker = ProjectShell.which("docker")
            ?? "\(NSHomeDirectory())/.docker/bin/docker"
        AppLog.info("Projects", "一键释放", [
            "project": projectName,
            "pids": pids.map(String.init).joined(separator: ","),
            "pidCount": pids.count,
            "containers": containers.count
        ])
        lastActionBanner = L10n.Projects.releasing

        Task.detached(priority: .userInitiated) {
            for pid in pids {
                let term = Self.signalPID(pid, sig: SIGTERM)
                AppLog.info("Projects", "已发 SIGTERM", [
                    "pid": pid,
                    "ok": term.ok,
                    "errno": term.errno
                ])
            }

            // 演示 LaunchAgent：直接 bootout，避免只杀进程看起来「没效果」。
            Self.bootoutDemoAgentIfNeeded(projectName: projectName)

            if FileManager.default.isExecutableFile(atPath: docker) {
                for id in containers {
                    _ = ProjectShell.run(docker, arguments: ["stop", "-t", "1", id], timeout: 4)
                }
            }

            // 最多约 600ms 轮询退出；仍存活再 SIGKILL，避免固定睡 1.1s。
            let deadline = Date().addingTimeInterval(0.6)
            while Date() < deadline, pids.contains(where: Self.isAlive) {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }

            for pid in pids where Self.isAlive(pid) {
                let killResult = Self.signalPID(pid, sig: SIGKILL)
                AppLog.info("Projects", "SIGTERM 未退，已 SIGKILL", [
                    "pid": pid,
                    "ok": killResult.ok,
                    "errno": killResult.errno
                ])
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            let deadPIDs = Set(pids.filter { !Self.isAlive($0) })
            let aliveAfter = pids.count - deadPIDs.count

            await MainActor.run {
                self.releasingIDs.remove(key)
                // 先从列表摘掉已死项，再后台采样核对——避免等下一次 3s poll / 目录重扫。
                self.pruneReleased(
                    groupID: key,
                    deadPIDs: deadPIDs,
                    stoppedContainers: Set(containers)
                )
                if aliveAfter == 0 {
                    self.lastActionBanner = L10n.Projects.releaseDone(projectName)
                    AppLog.info("Projects", "释放完成，已即时更新列表", [
                        "project": projectName,
                        "removedPIDs": deadPIDs.count
                    ])
                } else {
                    self.lastActionBanner = L10n.Projects.releasePartial(projectName, aliveAfter)
                    AppLog.warn("Projects", "释放后仍有进程存活", [
                        "project": projectName,
                        "alive": aliveAfter
                    ])
                }
                self.refresh(reason: "afterRelease")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if self.lastActionBanner != nil {
                        self.lastActionBanner = nil
                    }
                }
            }
        }
    }

    /// 释放成功后立刻改 UI，不等采样回来。
    private func pruneReleased(groupID: String, deadPIDs: Set<Int32>, stoppedContainers: Set<String>) {
        guard !deadPIDs.isEmpty || !stoppedContainers.isEmpty else { return }
        var next: [ProjectRuntimeGroup] = []
        for group in groups {
            let kept = group.items.filter { item in
                if let pid = item.pid, deadPIDs.contains(pid) { return false }
                if let cid = item.containerID, stoppedContainers.contains(cid) { return false }
                return true
            }
            if kept.isEmpty { continue }
            if kept.count == group.items.count {
                next.append(group)
                continue
            }
            next.append(
                ProjectRuntimeGroup(
                    id: group.id,
                    project: group.project,
                    items: kept,
                    totalCPU: kept.reduce(0) { $0 + $1.cpuPercent },
                    totalMemory: kept.reduce(0) { $0 + $1.memoryBytes }
                )
            )
        }
        groups = next
        AppLog.debug("Projects", "列表已乐观摘除已释放项", [
            "group": groupID,
            "deadPIDs": deadPIDs.count,
            "containers": stoppedContainers.count,
            "groupsLeft": next.count
        ])
    }

    nonisolated private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// 优先 Darwin kill；失败再用 /bin/kill。
    nonisolated private static func signalPID(_ pid: Int32, sig: Int32) -> (ok: Bool, errno: Int32) {
        if kill(pid, sig) == 0 {
            return (true, 0)
        }
        let first = Darwin.errno
        let flag: String
        switch sig {
        case SIGTERM: flag = "-TERM"
        case SIGKILL: flag = "-KILL"
        case SIGINT: flag = "-INT"
        default: flag = "-\(sig)"
        }
        let result = ProjectShell.run("/bin/kill", arguments: [flag, String(pid)], timeout: 2)
        let ok = result.exitCode == 0
        if !ok {
            AppLog.warn("Projects", "/bin/kill 失败", [
                "pid": pid,
                "sig": flag,
                "code": result.exitCode,
                "stderr": String(result.stderr.prefix(80)),
                "darwinErrno": first
            ])
        }
        return (ok, first)
    }

    nonisolated private static func bootoutDemoAgentIfNeeded(projectName: String) {
        let map = [
            "Ridge": "app.daphnis.ridge.demo.ridge",
            "Focal": "app.daphnis.ridge.demo.focal",
            "daphnis-apps": "app.daphnis.ridge.demo.daphnis-apps"
        ]
        guard let label = map[projectName] else { return }
        let uid = getuid()
        let target = "gui/\(uid)/\(label)"
        let result = ProjectShell.run("/bin/launchctl", arguments: ["bootout", target], timeout: 3)
        AppLog.info("Projects", "尝试 bootout 演示 Agent", [
            "label": label,
            "code": result.exitCode,
            "stderr": String(result.stderr.prefix(80))
        ])
    }

    func isReleasing(_ group: ProjectRuntimeGroup) -> Bool {
        releasingIDs.contains(group.id)
    }

    /// 可释放的项目组（左侧 Running）；未归属端口排在末尾。
    var runningGroups: [ProjectRuntimeGroup] {
        let attributed = groups.filter { $0.project != nil }
        let orphans = groups.filter { $0.project == nil }
        return attributed + orphans
    }

    var containerItems: [ProjectRuntimeItem] {
        groups.flatMap(\.items).filter { $0.kind == .container }
    }

    var activeWatch: ProjectWatchTarget? {
        watches.first
    }

    func toggleWatch(item: ProjectRuntimeItem, projectName: String) {
        guard let pid = item.pid else { return }
        // 再次点同一进程 → 取消；点其它进程 → 切换（同时只监视一个）。
        if watches.contains(where: { $0.pid == pid }) {
            cancelExitTask(pid: pid)
            watches.removeAll { $0.pid == pid }
            AppLog.info("Projects", "取消 Watch", ["pid": pid])
            return
        }
        let previous = watches.first?.projectName
        for old in watches {
            cancelExitTask(pid: old.pid)
        }
        let processStartedAt = item.startedAt
            ?? ProjectProcessSupport.startDate(pid: pid)
            ?? Date()
        let logPath = ProjectProcessSupport.discoverLogPath(pid: pid)
        let mem = item.memoryBytes
        let target = ProjectWatchTarget(
            id: "watch:\(pid)",
            pid: pid,
            label: item.title,
            projectName: projectName,
            startedAt: processStartedAt,
            logPath: logPath,
            lastMemoryBytes: mem,
            peakMemoryBytes: mem
        )
        watches = [target]
        // 换监视对象：清掉上一份结束提示，避免岛上 / 控制台仍显示被替换进程。
        clearWatchEndedNotice(reason: "replaced")
        beginExitMonitor(for: target)
        AppLog.info("Projects", "开始 Watch", [
            "pid": pid,
            "label": item.title,
            "project": projectName,
            "replaced": previous ?? "",
            "startedAt": ISO8601DateFormatter().string(from: processStartedAt),
            "hasLog": logPath != nil,
            "memoryBytes": mem
        ])
    }

    /// 监视该组主进程；已在监视则取消，否则切换为当前组。
    func toggleWatchPrimary(in group: ProjectRuntimeGroup) {
        let projectName = group.project?.name ?? L10n.Projects.unattributed
        guard let item = group.items
            .filter({ $0.kind == .process && $0.pid != nil })
            .max(by: { $0.cpuPercent < $1.cpuPercent })
        else {
            AppLog.debug("Projects", "无可监视进程", ["group": group.id])
            return
        }
        toggleWatch(item: item, projectName: projectName)
    }

    func stopWatch(_ target: ProjectWatchTarget) {
        cancelExitTask(pid: target.pid)
        watches.removeAll { $0.id == target.id }
        AppLog.info("Projects", "停止 Watch", ["pid": target.pid])
    }

    func isWatching(pid: Int32?) -> Bool {
        guard let pid else { return false }
        return watches.contains(where: { $0.pid == pid })
    }

    func isWatching(group: ProjectRuntimeGroup) -> Bool {
        let pids = Set(group.items.compactMap(\.pid))
        return watches.contains { pids.contains($0.pid) }
    }

    func openWatchLogs(for target: ProjectWatchTarget) {
        openLogs(path: target.logPath, context: "watching", pid: target.pid)
    }

    func openEndedWatchLogs() {
        openLogs(path: lastWatchEnded?.logPath, context: "ended", pid: nil)
    }

    private func openLogs(path: String?, context: String, pid: Int32?) {
        guard let path, !path.isEmpty else {
            lastActionBanner = L10n.Projects.logNotFound
            AppLog.warn("Projects", "未找到可打开的进程日志", [
                "context": context,
                "pid": pid ?? 0
            ])
            return
        }
        let ok = ProjectProcessSupport.openLog(at: path)
        if ok {
            AppLog.info("Projects", "已打开进程日志", [
                "context": context,
                "path": (path as NSString).lastPathComponent
            ])
        } else {
            lastActionBanner = L10n.Projects.logOpenFailed
            AppLog.warn("Projects", "打开进程日志失败", [
                "context": context,
                "path": path
            ])
        }
    }

    private func beginExitMonitor(for target: ProjectWatchTarget) {
        cancelExitTask(pid: target.pid)
        let pid = target.pid
        let flag = WatchCancelFlag()
        let task = Task { [weak self] in
            let outcome = await ProjectProcessSupport.waitForExit(pid: pid) {
                flag.cancelled
            }
            guard let outcome else { return }
            await MainActor.run {
                guard let self else { return }
                self.exitMonitors[pid] = nil
                self.publishWatchEnded(target: target, outcome: outcome)
            }
        }
        exitMonitors[pid] = ExitMonitor(task: task, cancel: flag)
    }

    private func cancelExitTask(pid: Int32) {
        if let monitor = exitMonitors.removeValue(forKey: pid) {
            monitor.cancel.cancelled = true
            monitor.task.cancel()
        }
    }

    /// 轮询兜底：kqueue 任务异常时仍能发现进程消失。
    private func checkWatches() {
        guard !watches.isEmpty else { return }
        var ended: [ProjectWatchTarget] = []
        for target in watches where kill(target.pid, 0) != 0 {
            // 有 kqueue 任务时交给它带退出码回调；否则本处兜底。
            if exitMonitors[target.pid] == nil {
                ended.append(target)
            }
        }
        for target in ended {
            publishWatchEnded(target: target, outcome: .unknown)
        }
    }

    /// 用最新采样刷新监视中进程的 RSS / 峰值（结束后无法再读）。
    private func refreshWatchMemory(from groups: [ProjectRuntimeGroup]) {
        guard !watches.isEmpty else { return }
        let byPID = Dictionary(
            uniqueKeysWithValues: groups.flatMap(\.items).compactMap { item -> (Int32, UInt64)? in
                guard let pid = item.pid, item.memoryBytes > 0 else { return nil }
                return (pid, item.memoryBytes)
            }
        )
        var changed = false
        var next = watches
        for i in next.indices {
            guard let mem = byPID[next[i].pid] else { continue }
            if next[i].lastMemoryBytes != mem || mem > next[i].peakMemoryBytes {
                next[i].lastMemoryBytes = mem
                next[i].peakMemoryBytes = max(next[i].peakMemoryBytes, mem)
                changed = true
            }
        }
        if changed {
            watches = next
            if let watch = next.first {
                AppLog.debug("Projects", "监视内存已更新", [
                    "pid": watch.pid,
                    "last": watch.lastMemoryBytes,
                    "peak": watch.peakMemoryBytes
                ])
            }
        }
    }

    private func publishWatchEnded(target: ProjectWatchTarget, outcome: ProjectWatchOutcome) {
        // 与控制台一致：只提示当前仍在监视列表里的进程；被第二个监控替换掉的不提示。
        guard let latest = watches.first(where: { $0.pid == target.pid }) else {
            cancelExitTask(pid: target.pid)
            AppLog.info("Projects", "Watch 已替换，跳过结束通知", [
                "pid": target.pid,
                "label": target.label,
                "outcome": String(describing: outcome)
            ])
            return
        }
        // 再采一次当前列表里的内存，尽量贴近结束前的最后值。
        refreshWatchMemory(from: groups)
        let refreshed = watches.first(where: { $0.pid == target.pid }) ?? latest
        watches.removeAll { $0.pid == target.pid }
        cancelExitTask(pid: target.pid)
        let peak = max(refreshed.peakMemoryBytes, refreshed.lastMemoryBytes)
        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(refreshed.startedAt))
        let message = L10n.Projects.watchEndedMessage(
            refreshed.projectName,
            refreshed.label,
            outcome,
            peakMemoryBytes: peak,
            durationSeconds: duration
        )
        let notice = ProjectWatchEndedNotice(
            id: "ended:\(refreshed.pid):\(UUID().uuidString)",
            projectName: refreshed.projectName,
            label: refreshed.label,
            message: message,
            endedAt: endedAt,
            outcome: outcome,
            logPath: refreshed.logPath,
            peakMemoryBytes: peak,
            durationSeconds: duration
        )
        lastWatchEnded = notice
        IslandNoticeCenter.shared.present(.processEnded(notice))
        AppLog.info("Projects", "Watch 进程已结束，交由瞬时通知上岛", [
            "pid": refreshed.pid,
            "project": refreshed.projectName,
            "label": refreshed.label,
            "outcome": String(describing: outcome),
            "hasLog": refreshed.logPath != nil,
            "peakMemoryBytes": peak,
            "durationSec": Int(duration)
        ])
    }

    func dismissWatchEnded() {
        clearWatchEndedNotice(reason: "dismiss")
    }

    private func clearWatchEndedNotice(reason: String) {
        let hadLocal = lastWatchEnded != nil
        let noticeID = lastWatchEnded?.id
        lastWatchEnded = nil
        if let noticeID {
            IslandNoticeCenter.shared.dismiss(id: noticeID)
        } else if case .processEnded = IslandNoticeCenter.shared.current {
            IslandNoticeCenter.shared.dismiss()
        }
        if hadLocal {
            AppLog.debug("Projects", "监视结束提示已清除", ["reason": reason])
        }
    }
}
