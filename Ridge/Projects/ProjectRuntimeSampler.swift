import Darwin
import Foundation

/// 采集进程 / 端口 / Docker，并按项目聚合。
enum ProjectRuntimeSampler {
    private struct LiveProcess {
        let pid: Int32
        let ppid: Int32
        let cpu: Double
        let memoryBytes: UInt64
        let command: String
    }

    private struct ListenSocket {
        let pid: Int32
        let port: Int
    }

    private struct LiveContainer {
        let id: String
        let name: String
        let image: String
        let ports: [Int]
        let workingDir: String?
        let projectName: String?
    }

    static func sample(projects: [ScannedProject], roots: [String] = []) -> [ProjectRuntimeGroup] {
        let started = Date()
        let processes = loadProcesses()
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let sockets = loadListenSockets()
        let containers = loadContainers()
        let expandedRoots = roots.map { ($0 as NSString).expandingTildeInPath.lowercased() }

        // 只给「监听端口」相关 pid（及短 ppid 链）批量查 cwd，避免对全机逐个 lsof。
        var cwdProbePIDs = Set(sockets.map(\.pid))
        for socket in sockets {
            var current: Int32? = socket.pid
            for _ in 0..<6 {
                guard let pid = current, let proc = byPID[pid] else { break }
                cwdProbePIDs.insert(pid)
                current = proc.ppid
                if current == 0 || current == 1 { break }
            }
        }
        let cwdByPID = loadCWDs(for: Array(cwdProbePIDs))

        var groupItems: [String: [ProjectRuntimeItem]] = [:]
        var claimedPIDs = Set<Int32>()
        var claimedPorts = Set<Int>()

        func append(projectKey: String, item: ProjectRuntimeItem) {
            groupItems[projectKey, default: []].append(item)
        }

        // 1) 命令行带路径，或已批量查到 cwd 的进程
        for process in processes {
            guard let hit = matchProject(
                command: process.command,
                cwd: cwdByPID[process.pid],
                projects: projects
            ) else { continue }
            claimedPIDs.insert(process.pid)
            let ports = sockets.filter { $0.pid == process.pid }.map(\.port).sorted()
            ports.forEach { claimedPorts.insert($0) }
            append(
                projectKey: hit.path,
                item: ProjectRuntimeItem(
                    id: "proc:\(process.pid)",
                    kind: .process,
                    title: displayCommand(process.command),
                    detail: "",
                    pid: process.pid,
                    containerID: nil,
                    ports: ports,
                    cpuPercent: process.cpu,
                    memoryBytes: process.memoryBytes,
                    startedAt: ProjectProcessSupport.startDate(pid: process.pid),
                    canRelease: true
                )
            )
        }

        // 2) 仍未归属的监听端口：用 cwd / 命令 / 父进程链归属
        for socket in sockets where !claimedPorts.contains(socket.port) {
            // 无 ps 命令行的监听（常见于 docker 端口转发残留）不展示，避免「未知进程」。
            guard let proc = byPID[socket.pid], !proc.command.isEmpty else { continue }
            if let hit = matchPort(
                socket: socket,
                byPID: byPID,
                cwdByPID: cwdByPID,
                projects: projects
            ) {
                claimedPorts.insert(socket.port)
                claimedPIDs.insert(socket.pid)
                append(
                    projectKey: hit.path,
                    item: ProjectRuntimeItem(
                        id: "port:\(socket.port):\(socket.pid)",
                        kind: .process,
                        title: displayCommand(proc.command),
                        detail: "",
                        pid: socket.pid,
                        containerID: nil,
                        ports: [socket.port],
                        cpuPercent: proc.cpu,
                        memoryBytes: proc.memoryBytes,
                        startedAt: ProjectProcessSupport.startDate(pid: socket.pid),
                        canRelease: true
                    )
                )
            }
        }

        // 3) Docker 容器
        for container in containers {
            let project = matchContainer(container, projects: projects)
            let key = project?.path ?? "__orphan__"
            append(
                projectKey: key,
                item: ProjectRuntimeItem(
                    id: "docker:\(container.id)",
                    kind: .container,
                    title: friendlyContainerName(container.name),
                    detail: shortImage(container.image),
                    pid: nil,
                    containerID: container.id,
                    ports: container.ports,
                    cpuPercent: 0,
                    memoryBytes: 0,
                    startedAt: nil,
                    canRelease: project != nil
                )
            )
            container.ports.forEach { claimedPorts.insert($0) }
        }

        // 4) 未归属：仅保留「落在扫描根目录下」却对不上项目的监听，避免系统端口刷屏。
        var orphanCount = 0
        var orphanSkipped = 0
        for socket in sockets where !claimedPorts.contains(socket.port) {
            let proc = byPID[socket.pid]
            let command = proc?.command ?? ""
            // 没有命令行的监听不进「未归属」，避免一排「未知进程」。
            guard !command.isEmpty else {
                orphanSkipped += 1
                continue
            }
            let cwd = cwdByPID[socket.pid]
            guard isUnderScanRoots(command: command, cwd: cwd, roots: expandedRoots) else {
                orphanSkipped += 1
                continue
            }
            orphanCount += 1
            append(
                projectKey: "__orphan__",
                item: ProjectRuntimeItem(
                    id: "orphan:\(socket.port):\(socket.pid)",
                    kind: .orphanPort,
                    title: displayCommand(command),
                    detail: "",
                    pid: socket.pid,
                    containerID: nil,
                    ports: [socket.port],
                    cpuPercent: proc?.cpu ?? 0,
                    memoryBytes: proc?.memoryBytes ?? 0,
                    startedAt: socket.pid == 0 ? nil : ProjectProcessSupport.startDate(pid: socket.pid),
                    canRelease: false
                )
            )
        }

        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        var groups: [ProjectRuntimeGroup] = []
        for (key, items) in groupItems {
            let uniqueItems = dedupe(items)
            guard !uniqueItems.isEmpty else { continue }
            let project = key == "__orphan__" ? nil : projectByPath[key]
            groups.append(
                ProjectRuntimeGroup(
                    id: key,
                    project: project,
                    items: uniqueItems.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    },
                    totalCPU: uniqueItems.reduce(0) { $0 + $1.cpuPercent },
                    totalMemory: uniqueItems.reduce(UInt64(0)) { $0 + $1.memoryBytes }
                )
            )
        }

        let attributed = groups.filter { $0.project != nil }.count
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.info("Projects", "运行时采样完成", [
            "projects": projects.count,
            "processes": processes.count,
            "sockets": sockets.count,
            "cwdHits": cwdByPID.count,
            "containers": containers.count,
            "attributedGroups": attributed,
            "orphanPorts": orphanCount,
            "orphanSkipped": orphanSkipped,
            "ms": ms
        ])
        writeDebugDump(
            projects: projects,
            groups: groups,
            cwdByPID: cwdByPID,
            sockets: sockets,
            ms: ms
        )

        return groups.sorted { lhs, rhs in
            switch (lhs.project, rhs.project) {
            case (.some, .none): return true
            case (.none, .some): return false
            case let (.some(a), .some(b)):
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case (.none, .none):
                return lhs.id < rhs.id
            }
        }
    }

    // MARK: - Match

    private static func matchProject(
        command: String,
        cwd: String?,
        projects: [ScannedProject]
    ) -> ScannedProject? {
        guard !projects.isEmpty else { return nil }
        let lower = command.lowercased()
        // 命令行可能同时带脚本路径与项目路径：取最长路径命中，避免都归到 Ridge/build。
        if !lower.isEmpty {
            let hits = projects.filter { lower.contains($0.path.lowercased()) }
            if let best = hits.max(by: { $0.path.count < $1.path.count }) {
                return best
            }
        }
        guard let cwd, !cwd.isEmpty else { return nil }
        let cwdLower = cwd.lowercased()
        return projects
            .filter { pathContained(cwdLower, projectPath: $0.path.lowercased()) }
            .max(by: { $0.path.count < $1.path.count })
    }

    private static func pathContained(_ path: String, projectPath: String) -> Bool {
        path == projectPath || path.hasPrefix(projectPath + "/")
    }

    private static func isUnderScanRoots(command: String, cwd: String?, roots: [String]) -> Bool {
        guard !roots.isEmpty else { return false }
        let commandLower = command.lowercased()
        if roots.contains(where: { commandLower.contains($0) }) {
            return true
        }
        guard let cwd else { return false }
        let cwdLower = cwd.lowercased()
        return roots.contains { pathContained(cwdLower, projectPath: $0) }
    }

    private static func writeDebugDump(
        projects: [ScannedProject],
        groups: [ProjectRuntimeGroup],
        cwdByPID: [Int32: String],
        sockets: [ListenSocket],
        ms: Int
    ) {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Ridge")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("projects-last.txt")
        var lines: [String] = []
        lines.append("ts=\(ISO8601DateFormatter().string(from: Date())) ms=\(ms) sockets=\(sockets.count)")
        lines.append("projects=\(projects.map(\.name).joined(separator: ","))")
        for group in groups {
            let name = group.project?.name ?? "未归属"
            let ports = group.items.flatMap(\.ports).map(String.init).joined(separator: ",")
            lines.append("group=\(name) items=\(group.items.count) ports=\(ports)")
            for item in group.items.prefix(8) {
                let portText = item.ports.isEmpty
                    ? ""
                    : " :" + item.ports.map(String.init).joined(separator: ",")
                let detail = item.detail.isEmpty ? "" : " (\(item.detail))"
                lines.append("  - \(item.kind.rawValue) \(item.title)\(portText)\(detail)")
            }
        }
        for (pid, cwd) in cwdByPID.sorted(by: { $0.key < $1.key }).prefix(24) {
            lines.append("cwd pid=\(pid) \(cwd)")
        }
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func matchPort(
        socket: ListenSocket,
        byPID: [Int32: LiveProcess],
        cwdByPID: [Int32: String],
        projects: [ScannedProject]
    ) -> ScannedProject? {
        var current: Int32? = socket.pid
        var guardCount = 0
        while let pid = current, guardCount < 12 {
            guardCount += 1
            let command = byPID[pid]?.command ?? ""
            if let project = matchProject(command: command, cwd: cwdByPID[pid], projects: projects) {
                return project
            }
            current = byPID[pid]?.ppid
            if current == 0 || current == 1 { break }
        }
        return nil
    }

    private static func matchContainer(
        _ container: LiveContainer,
        projects: [ScannedProject]
    ) -> ScannedProject? {
        let haystacks = [container.workingDir, container.projectName, container.name, container.image]
            .compactMap { $0?.lowercased() }
        for project in projects {
            let path = project.path.lowercased()
            let name = project.name.lowercased()
            if haystacks.contains(where: { $0.contains(path) || $0 == name || $0.contains(name) }) {
                return project
            }
        }
        return nil
    }

    // MARK: - Loaders

    private static func loadProcesses() -> [LiveProcess] {
        // -ww：避免命令行被截断导致路径匹配失败
        let result = ProjectShell.run(
            "/bin/ps",
            arguments: ["-axww", "-o", "pid=,ppid=,pcpu=,rss=,command="],
            timeout: 6
        )
        guard result.exitCode == 0 else {
            AppLog.warn("Projects", "ps 失败", [
                "code": result.exitCode,
                "stderr": String(result.stderr.prefix(120))
            ])
            return []
        }
        return result.stdout.split(whereSeparator: \.isNewline).compactMap { line -> LiveProcess? in
            let raw = String(line).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            let parts = raw.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]),
                  let rssKB = UInt64(parts[3])
            else { return nil }
            let command = parts.dropFirst(4).joined(separator: " ")
            if shouldIgnore(command: command) { return nil }
            return LiveProcess(
                pid: pid,
                ppid: ppid,
                cpu: cpu,
                memoryBytes: rssKB * 1024,
                command: command
            )
        }
    }

    private static func loadListenSockets() -> [ListenSocket] {
        let human = ProjectShell.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"],
            timeout: 6
        )
        guard human.exitCode == 0 || !human.stdout.isEmpty else {
            AppLog.warn("Projects", "lsof 监听枚举失败", [
                "code": human.exitCode,
                "stderr": String(human.stderr.prefix(120))
            ])
            return []
        }
        var sockets: [ListenSocket] = []
        for line in human.stdout.split(whereSeparator: \.isNewline).dropFirst() {
            let cols = String(line).split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 9, let pid = Int32(cols[1]) else { continue }
            let name = cols[8...].joined(separator: " ")
            guard let port = parsePort(from: name) else { continue }
            sockets.append(ListenSocket(pid: pid, port: port))
        }
        return sockets
    }

    /// 优先 libproc 读 cwd（同用户进程通常可用）；不足再批量 lsof 补洞。
    private static func loadCWDs(for pids: [Int32]) -> [Int32: String] {
        let unique = Array(Set(pids)).filter { $0 > 0 }.sorted()
        guard !unique.isEmpty else { return [:] }

        var map: [Int32: String] = [:]
        for pid in unique {
            if let cwd = cwdViaLibproc(pid) {
                map[pid] = cwd
            }
        }

        let missing = unique.filter { map[$0] == nil }
        if !missing.isEmpty {
            let viaLsof = cwdViaLsof(pids: missing)
            for (pid, cwd) in viaLsof {
                map[pid] = cwd
            }
            AppLog.debug("Projects", "cwd 解析", [
                "wanted": unique.count,
                "libproc": unique.count - missing.count,
                "lsof": viaLsof.count,
                "miss": unique.count - map.count
            ])
        }
        return map
    }

    private static func cwdViaLibproc(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let got = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard got > 0 else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    private static func cwdViaLsof(pids: [Int32]) -> [Int32: String] {
        var map: [Int32: String] = [:]
        let chunkSize = 40
        var offset = 0
        while offset < pids.count {
            let end = min(offset + chunkSize, pids.count)
            let chunk = Array(pids[offset..<end])
            offset = end
            let pidList = chunk.map(String.init).joined(separator: ",")
            let result = ProjectShell.run(
                "/usr/sbin/lsof",
                arguments: ["-a", "-d", "cwd", "-Fn", "-p", pidList],
                timeout: 4
            )
            if result.exitCode != 0 && result.stdout.isEmpty {
                AppLog.debug("Projects", "批量 cwd 查询失败", [
                    "count": chunk.count,
                    "code": result.exitCode
                ])
                continue
            }
            var currentPID: Int32?
            for line in result.stdout.split(whereSeparator: \.isNewline) {
                let s = String(line)
                if s.hasPrefix("p"), let pid = Int32(s.dropFirst()) {
                    currentPID = pid
                } else if s.hasPrefix("n"), let pid = currentPID {
                    map[pid] = String(s.dropFirst())
                }
            }
        }
        return map
    }

    private static func loadContainers() -> [LiveContainer] {
        guard let docker = ProjectShell.which("docker") ?? optionalDockerPath() else {
            return []
        }
        let format = "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Label \"com.docker.compose.project.working_dir\"}}\t{{.Label \"com.docker.compose.project\"}}"
        let result = ProjectShell.run(docker, arguments: ["ps", "--format", format])
        guard result.exitCode == 0 else {
            AppLog.debug("Projects", "docker ps 不可用", ["stderr": String(result.stderr.prefix(80))])
            return []
        }
        return result.stdout.split(whereSeparator: \.isNewline).compactMap { line -> LiveContainer? in
            let parts = String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { return nil }
            return LiveContainer(
                id: parts[0],
                name: parts[1],
                image: parts[2],
                ports: parseDockerPorts(parts[3]),
                workingDir: parts.count > 4 && !parts[4].isEmpty ? parts[4] : nil,
                projectName: parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil
            )
        }
    }

    private static func optionalDockerPath() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(NSHomeDirectory())/.docker/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Helpers

    private static func shouldIgnore(command: String) -> Bool {
        let lower = command.lowercased()
        if lower.contains("/applications/ridge.app") { return true }
        if lower.hasPrefix("ps ") || lower == "ps" { return true }
        if lower.contains("lsof ") { return true }
        // docker-proxy / 虚拟机辅助进程对用户无意义，且会污染「同项目多进程」。
        if lower.contains("docker-proxy") { return true }
        if lower.contains("com.docker") { return true }
        if lower.contains("/colima/") || lower.contains("limactl") { return true }
        // 本仓库验收 keeper / IDE 辅助进程（勿当作用户开发进程）
        if lower.contains("keep-six-procs") { return true }
        if lower.contains("/applications/cursor.app") { return true }
        if lower.contains("cursor helper") { return true }
        if lower.contains("cursor-agent") { return true }
        if lower.contains("anysphere.cursor") { return true }
        if lower.contains("/library/application support/cursor/") { return true }
        return false
    }

    /// 用户可读进程名：只展示脚本 / 入口短名，不带 python3 / node 等解释器前缀。
    private static func displayCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.Projects.unknownProcess }

        // 优先整串匹配脚本名，避免「Application Support」空格把路径拆碎成诡异标题。
        if let script = extractScriptBasename(from: trimmed) {
            return script
        }

        let parts = tokenizeCommand(trimmed)
        guard let first = parts.first else { return L10n.Projects.unknownProcess }

        let rawBin = (first as NSString).lastPathComponent
        let bin = normalizeBinaryName(rawBin)

        // npm / pnpm / yarn / bun run <script> — 包管理命令本身就是进程身份。
        if ["npm", "pnpm", "yarn", "bun"].contains(bin.lowercased()),
           parts.count >= 3,
           parts[1] == "run" {
            return "\(bin) run \(parts[2])"
        }

        // 找第一个像入口文件的参数
        for arg in parts.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let base = (arg as NSString).lastPathComponent
            if base.isEmpty || (base == arg && !arg.contains("/") && arg.count > 24) {
                // 过长且无路径的 token（hash 等）跳过
                continue
            }
            let lower = base.lowercased()
            if lower.hasSuffix(".py")
                || lower.hasSuffix(".js")
                || lower.hasSuffix(".mjs")
                || lower.hasSuffix(".cjs")
                || lower.hasSuffix(".ts")
                || lower.hasSuffix(".tsx")
                || lower.hasSuffix(".jsx")
                || lower.hasSuffix(".rb")
                || lower.hasSuffix(".go")
                || lower.hasSuffix(".sh")
                || lower == "main"
                || lower.hasPrefix("vite")
                || lower.hasPrefix("next")
                || lower.hasPrefix("webpack") {
                return base
            }
        }

        // 退一步：第一个非 flag 参数短名（仍不带解释器）。
        for arg in parts.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let base = (arg as NSString).lastPathComponent
            if base.isEmpty { continue }
            if base.count > 40 { continue }
            return base
        }

        return bin
    }

    /// 把被空格拆开的绝对路径尽量拼回（如 `/Library/Application Support/...`）。
    private static func tokenizeCommand(_ command: String) -> [String] {
        let raw = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !raw.isEmpty else { return [] }
        var out: [String] = []
        var i = 0
        while i < raw.count {
            var token = raw[i]
            if token.hasPrefix("/") {
                while i + 1 < raw.count {
                    let next = raw[i + 1]
                    if next.hasPrefix("-") || next.hasPrefix("/") || next.hasPrefix("~") { break }
                    // 仅在当前片段不像完整可执行路径时续拼
                    let looksComplete = token.contains(".app/")
                        || token.lowercased().hasSuffix(".py")
                        || token.lowercased().hasSuffix(".js")
                        || token.lowercased().hasSuffix(".sh")
                        || FileManager.default.isExecutableFile(atPath: token)
                    if looksComplete { break }
                    token += " " + next
                    i += 1
                }
            }
            out.append(token)
            i += 1
        }
        return out
    }

    private static func extractScriptBasename(from command: String) -> String? {
        let pattern = #"([\w.+-]+\.(?:py|js|mjs|cjs|ts|tsx|jsx|rb|go|sh))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = command as NSString
        let matches = regex.matches(in: command, options: [], range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let name = ns.substring(with: match.range(at: 1))
            // 跳过过短/无意义
            if name.count < 3 { continue }
            return name
        }
        return nil
    }

    private static func normalizeBinaryName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.hasPrefix("python") { return "python3" }
        if lower == "node" || lower.hasPrefix("node") { return "node" }
        if lower == "ruby" { return "ruby" }
        if lower.hasPrefix("java") { return "java" }
        return raw
    }

    private static func friendlyContainerName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return L10n.Projects.unknownContainer }
        // compose 常带项目前缀 dir-service-1 → 保留原名即可，已比 hash 可读
        return trimmed
    }

    private static func shortImage(_ image: String) -> String {
        // nginx:alpine / ghcr.io/foo/bar:tag → 末段
        if let last = image.split(separator: "/").last {
            return String(last)
        }
        return image
    }

    private static func parsePort(from name: String) -> Int? {
        if let range = name.range(of: #"[:\*](\d{2,5})\b"#, options: .regularExpression) {
            let digits = name[range].filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }

    private static func parseDockerPorts(_ raw: String) -> [Int] {
        var ports: [Int] = []
        let regex = try? NSRegularExpression(pattern: #"(\d+)(?=/tcp|->)"#)
        let ns = raw as NSString
        let matches = regex?.matches(in: raw, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in matches {
            if match.numberOfRanges > 1,
               let port = Int(ns.substring(with: match.range(at: 1))) {
                ports.append(port)
            }
        }
        return Array(Set(ports)).sorted()
    }

    private static func dedupe(_ items: [ProjectRuntimeItem]) -> [ProjectRuntimeItem] {
        var seen = Set<String>()
        var result: [ProjectRuntimeItem] = []
        for item in items {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        return result
    }
}
