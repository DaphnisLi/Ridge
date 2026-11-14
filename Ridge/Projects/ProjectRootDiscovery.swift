import Foundation

/// 只发现「当前用户自己的」工程扫描目录。
/// - 仅扫 `NSHomeDirectory()`，不扫其它用户、不扫 `/Volumes` 别名盘
/// - 跳过 Flutter SDK / CocoaPods / 工具链噪音
/// - 扫描根只收「家目录下第一层」工作区（如 `~/project`），不收每个子工程路径
enum ProjectRootDiscovery {
    struct Result: Sendable {
        var roots: [String]
        var projectCount: Int
    }

    /// 家目录顶层直接跳过（媒体 / 系统习惯目录 / 工具链）。
    private static let homeTopSkip: Set<String> = [
        "Library", "Movies", "Music", "Pictures", "Public", "Applications",
        "Downloads", "Desktop", "Documents",
        // 工具链与备份，不是业务工程父目录
        "flutter", "go", "emsdk"
    ]

    private static let homeTopSkipPrefixes: [String] = [
        "flutter_", "flutter-", "CocoaPods", "."
    ]

    private static let skipDirectoryNames: Set<String> = [
        "node_modules", "target", "dist", "build", ".git", "Pods", "vendor",
        "DerivedData", ".build", ".next", ".turbo", ".cache", "__pycache__",
        "coverage", ".venv", "venv", "Carthage", "Library", "Applications",
        ".pub-cache", ".gradle", ".m2", ".cargo", ".rustup", ".nvm",
        "site-packages", "gems"
    ]

    /// 路径片段：命中则视为第三方 / SDK 内部工程，丢弃。
    private static let junkPathFragments: [String] = [
        "/flutter/packages/",
        "/flutter/examples/",
        "/flutter/dev/",
        "/flutter/engine/",
        "/flutter_tools/",
        "/.pub-cache/",
        "/.gradle/",
        "/.m2/",
        "/.cargo/",
        "/site-packages/",
        "/homebrew/",
        "/Homebrew/",
        "/Cellar/",
        "/opt/homebrew/",
        "/CocoaPods",
        "/gems/",
        "/node_modules/"
    ]

    static func discover() -> Result {
        let started = Date()
        let home = NSHomeDirectory()
        var workspaceRoots = Set<String>()
        var projectCount = 0

        walkHomeWorkspaces(
            home: home,
            intoRoots: &workspaceRoots,
            projectCount: &projectCount
        )

        // 进程 cwd 仅作补充：只接受落在家目录、且能归到顶层工作区的。
        for root in discoverRuntimeWorkspaceRoots(home: home) {
            workspaceRoots.insert(root)
        }

        let list = workspaceRoots.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        AppLog.warn("Projects", "已发现本人扫描根", [
            "roots": list.count,
            "projects": projectCount,
            "ms": Int(Date().timeIntervalSince(started) * 1000),
            "paths": list.prefix(12).joined(separator: ",")
        ])
        return Result(roots: list, projectCount: projectCount)
    }

    // MARK: - 仅当前用户家目录

    private static func walkHomeWorkspaces(
        home: String,
        intoRoots: inout Set<String>,
        projectCount: inout Int
    ) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: home) else { return }
        for name in names {
            if shouldSkipHomeTop(name) { continue }
            let top = (home as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: top, isDirectory: &isDir), isDir.boolValue else { continue }

            var found = 0
            collectProjects(
                top,
                depth: 0,
                maxDepth: 5,
                count: &found
            )
            if found > 0 {
                intoRoots.insert("~/\(name)")
                projectCount += found
            }
        }
    }

    private static func shouldSkipHomeTop(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if homeTopSkip.contains(name) { return true }
        let lower = name.lowercased()
        return homeTopSkipPrefixes.contains { lower.hasPrefix($0.lowercased()) || name.hasPrefix($0) }
    }

    private static func collectProjects(
        _ path: String,
        depth: Int,
        maxDepth: Int,
        count: inout Int
    ) {
        if isJunkProjectPath(path) { return }
        if ProjectCatalog.identifyPublic(at: path) != nil {
            count += 1
            // 命中工程后不再深入（避免 Flutter monorepo 式噪声）
            return
        }
        guard depth < maxDepth else { return }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: path) else { return }
        for name in children {
            if name.hasPrefix(".") { continue }
            if skipDirectoryNames.contains(name) { continue }
            let child = (path as NSString).appendingPathComponent(name)
            if isJunkProjectPath(child) { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
            collectProjects(child, depth: depth + 1, maxDepth: maxDepth, count: &count)
        }
    }

    private static func isJunkProjectPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return junkPathFragments.contains { lower.contains($0.lowercased()) }
    }

    // MARK: - 进程补充（仍限制在本人家目录顶层）

    private static func discoverRuntimeWorkspaceRoots(home: String) -> Set<String> {
        var roots = Set<String>()
        let processes = ProjectRuntimeSampler.loadProcessesForDiscovery()
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let sockets = ProjectRuntimeSampler.loadListenSocketsForDiscovery()

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
        for process in processes where process.command.contains(home) {
            cwdProbePIDs.insert(process.pid)
        }
        let cwdByPID = ProjectRuntimeSampler.loadCWDsForDiscovery(for: Array(cwdProbePIDs.prefix(200)))
        for cwd in cwdByPID.values {
            if let root = workspaceRootUnderHome(cwd, home: home) {
                roots.insert(root)
            }
        }
        return roots
    }

    /// `/Users/me/project/Ridge/src` → `~/project`；非家目录或 junk → nil。
    private static func workspaceRootUnderHome(_ path: String, home: String) -> String? {
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix(home + "/") else { return nil }
        if isJunkProjectPath(standardized) { return nil }
        let rel = String(standardized.dropFirst(home.count + 1))
        guard let first = rel.split(separator: "/").first else { return nil }
        let name = String(first)
        if shouldSkipHomeTop(name) { return nil }
        return "~/\(name)"
    }
}
