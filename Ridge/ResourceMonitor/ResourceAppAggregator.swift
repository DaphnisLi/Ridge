import AppKit
import Foundation

/// 按 App 聚合 RSS / CPU。
/// `ps` 的 `%CPU` 按单核计（可 >100）；入库前折成整机占比（100% = 全部核打满）。
enum ResourceAppAggregator {
    struct RawProcess: Sendable {
        var pid: Int32
        var ppid: Int32
        /// 整机 CPU 占比 0…100（已按核数归一）。
        var cpu: Double
        var memoryBytes: UInt64
        var command: String
    }

    /// 活跃逻辑核数；至少按 1，避免除零。
    nonisolated private static var cpuCoreCount: Double {
        Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
    }

    /// 单核 `%CPU` → 整机百分比。
    nonisolated static func normalizedCPUPercent(_ pcpu: Double) -> Double {
        min(100, max(0, pcpu / cpuCoreCount))
    }

    /// 前台 App 轻量描述，便于在后台线程聚合（避免主线程扫进程树）。
    struct RunningAppSeed: Sendable {
        var bundleID: String
        var name: String
        var rootPID: Int32
    }

    struct ProcessLoad: Sendable {
        var processes: [RawProcess]
        /// 可解析的进程行数（含被过滤的系统项）≈ 系统内核托管总量。
        var kernelHostedCount: Int
    }

    /// 仅跑 `ps`（可在后台线程）。
    nonisolated static func loadProcesses() -> ProcessLoad {
        let result = ProjectShell.run(
            "/bin/ps",
            arguments: ["-axww", "-o", "pid=,ppid=,pcpu=,rss=,command="],
            timeout: 3
        )
        guard result.exitCode == 0 else { return ProcessLoad(processes: [], kernelHostedCount: 0) }
        var kept: [RawProcess] = []
        var hosted = 0
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let parts = raw.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]),
                  let rssKB = UInt64(parts[3])
            else { continue }
            hosted += 1
            let command = parts.dropFirst(4).joined(separator: " ")
            if shouldSkip(command: command) { continue }
            kept.append(
                RawProcess(
                    pid: pid,
                    ppid: ppid,
                    cpu: normalizedCPUPercent(cpu),
                    memoryBytes: rssKB * 1024,
                    command: command
                )
            )
        }
        return ProcessLoad(processes: kept, kernelHostedCount: hosted)
    }

    /// 须在主线程：只读 `NSWorkspace`，不做进程树扫描。
    @MainActor
    static func runningAppSeeds() -> [RunningAppSeed] {
        // 含 Ridge 自身，便于对照本进程内存。
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let bid = app.bundleIdentifier, !bid.isEmpty,
                  app.processIdentifier > 0
            else { return nil }
            return RunningAppSeed(
                bundleID: bid,
                name: app.localizedName ?? bid,
                rootPID: app.processIdentifier
            )
        }
    }

    /// 主线程：用 `NSRunningApplication.localizedName` 覆盖友好名（Electron Helper 等）。
    @MainActor
    static func enrichChildTitles(_ apps: [ResourceAppUsage]) -> [ResourceAppUsage] {
        apps.map { app in
            var copy = app
            copy.children = copy.children.map { child in
                var next = child
                if let running = NSRunningApplication(processIdentifier: child.pid),
                   let name = running.localizedName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty
                {
                    next.title = truncateTitle(name)
                }
                // 否则保留聚合阶段从 command 解析的友好名。
                return next
            }
            return copy
        }
    }

    /// 后台可调用：用 ppid 索引做 O(n) 聚合。
    nonisolated static func topApps(
        from raw: [RawProcess],
        seeds: [RunningAppSeed],
        limit: Int = 5
    ) -> (apps: [ResourceAppUsage], monitoredCount: Int) {
        let byPID = Dictionary(uniqueKeysWithValues: raw.map { ($0.pid, $0) })
        var childrenByPPID: [Int32: [Int32]] = [:]
        childrenByPPID.reserveCapacity(raw.count)
        for proc in raw {
            childrenByPPID[proc.ppid, default: []].append(proc.pid)
        }

        var groups: [String: ResourceAppUsage] = [:]

        for seed in seeds {
            let tree = collectTree(root: seed.rootPID, byPID: byPID, childrenByPPID: childrenByPPID)
            guard !tree.isEmpty else { continue }

            let mem = tree.reduce(UInt64(0)) { $0 + $1.memoryBytes }
            // 进程树相加后仍限制在整机 0…100，避免展示再破百。
            let cpu = min(100, tree.reduce(0.0) { $0 + $1.cpu })
            // 数据多留一些，UI 可见区只露 5 行、可下滑。
            let children: [ResourceChildProcess] = tree
                .filter { $0.pid != seed.rootPID }
                .sorted { $0.memoryBytes > $1.memoryBytes }
                .prefix(32)
                .map { proc in
                    ResourceChildProcess(
                        pid: proc.pid,
                        title: friendlyTitle(command: proc.command),
                        memoryBytes: proc.memoryBytes,
                        cpuPercent: proc.cpu,
                        canKill: true
                    )
                }

            let existing = groups[seed.bundleID]
            let mergedChildren = ((existing?.children ?? []) + children)
                .sorted { $0.memoryBytes > $1.memoryBytes }
            groups[seed.bundleID] = ResourceAppUsage(
                bundleID: seed.bundleID,
                name: seed.name,
                mainPID: existing?.mainPID ?? seed.rootPID,
                memoryBytes: (existing?.memoryBytes ?? 0) + mem,
                cpuPercent: min(100, (existing?.cpuPercent ?? 0) + cpu),
                childCount: (existing?.childCount ?? 0) + max(0, tree.count - 1),
                children: Array(mergedChildren.prefix(32))
            )
        }

        let ranked = groups.values
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(limit)
            .map { app -> ResourceAppUsage in
                var copy = app
                if copy.children.isEmpty { copy.childCount = 0 }
                return copy
            }

        return (Array(ranked), raw.count)
    }


    private nonisolated static func collectTree(
        root: Int32,
        byPID: [Int32: RawProcess],
        childrenByPPID: [Int32: [Int32]]
    ) -> [RawProcess] {
        var result: [RawProcess] = []
        var queue: [Int32] = [root]
        var seen = Set<Int32>()
        var head = 0
        while head < queue.count {
            let pid = queue[head]
            head += 1
            guard seen.insert(pid).inserted else { continue }
            guard let proc = byPID[pid] else { continue }
            result.append(proc)
            if let kids = childrenByPPID[pid] {
                queue.append(contentsOf: kids)
            }
        }
        return result
    }

    private nonisolated static func shouldSkip(command: String) -> Bool {
        let lower = command.lowercased()
        if lower.contains("kernel_task") { return true }
        if lower.hasPrefix("/sbin/") || lower.hasPrefix("/usr/libexec/") { return true }
        return false
    }

    /// 从 `ps` command 抽可读名：优先 `Foo.app/Contents/MacOS/Bar`，跳过纯参数段。
    nonisolated static func friendlyTitle(command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }

        if let appRange = trimmed.range(
            of: #"[^/\s]+\.app/Contents/(MacOS|Helpers)/[^/\s]+"#,
            options: .regularExpression
        ) {
            let path = String(trimmed[appRange])
            let leaf = (path as NSString).lastPathComponent
            return truncateTitle(decorateHelper(leaf: leaf, command: trimmed))
        }

        for token in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            let t = String(token)
            if t.hasPrefix("-") || t.hasPrefix("=") || t.hasPrefix("*") { continue }
            if t.contains("/") {
                let leaf = (t as NSString).lastPathComponent
                if leaf.isEmpty { continue }
                return truncateTitle(decorateHelper(leaf: leaf, command: trimmed))
            }
            if t.count >= 2, t.rangeOfCharacter(from: .letters) != nil {
                return truncateTitle(t)
            }
        }

        let base = (trimmed as NSString).lastPathComponent
        return truncateTitle(base.isEmpty ? trimmed : base)
    }

    nonisolated private static func decorateHelper(leaf: String, command: String) -> String {
        // Chromium / Electron：`Helper (Renderer)` 常写在 argv0 后。
        if let role = command.range(of: #"\((Renderer|GPU|Plugin|Service|Extension|Alert)[^)]*\)"#, options: [.regularExpression, .caseInsensitive]) {
            let roleText = String(command[role])
            if !leaf.contains(roleText) {
                return "\(leaf) \(roleText)"
            }
        }
        return leaf
    }

    nonisolated private static func truncateTitle(_ title: String) -> String {
        if title.count > 52 { return String(title.prefix(49)) + "…" }
        return title
    }
}
