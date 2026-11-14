import Combine
import Foundation

/// 项目释放模块偏好：扫描根目录（仅当前用户本人工作区）。
@MainActor
final class ProjectSettings: ObservableObject {
    static let shared = ProjectSettings()

    private enum Key {
        static let roots = "projects.roots.v1"
        static let clearedLegacyDefaults = "projects.roots.clearedLegacyDefaults.v1"
        /// 清掉 Volumes / Homebrew / Flutter SDK 误扫残留后，按本人工作区重发现一次。
        static let sanitizedPersonalOnly = "projects.roots.sanitizedPersonalOnly.v2"
    }

    private static let legacyDefaultRoots = [
        "~/project", "~/code", "~/Developer", "~/Projects"
    ]

    @Published var roots: [String] {
        didSet {
            UserDefaults.standard.set(roots, forKey: Key.roots)
            AppLog.info("Projects", "已更新项目根目录", ["count": roots.count])
            guard isReady else { return }
            ProjectReleaseSession.shared.refresh(reason: "rootsChanged")
        }
    }

    private var isReady = false

    private init() {
        let defaults = UserDefaults.standard
        var stored = defaults.array(forKey: Key.roots) as? [String] ?? []

        if !defaults.bool(forKey: Key.clearedLegacyDefaults) {
            let before = stored
            stored = stored.filter { path in
                !Self.legacyDefaultRoots.contains(where: { Self.samePath($0, path) })
            }
            defaults.set(true, forKey: Key.clearedLegacyDefaults)
            if stored != before {
                AppLog.warn("Projects", "已清除历史默认扫描目录", [
                    "dropped": before.count - stored.count
                ])
            }
        }

        // 立刻丢掉误扫脏数据（Volumes 别名、Homebrew、Flutter SDK 等）。
        let beforeSanitize = stored.count
        stored = stored.filter(Self.isPersonalWorkspaceRoot)
        if stored.count != beforeSanitize {
            AppLog.warn("Projects", "已剔除非本人工作区扫描根", [
                "before": beforeSanitize,
                "after": stored.count
            ])
        }

        roots = stored
        isReady = true
        AppLog.warn("Projects", "已加载项目设置", [
            "roots": roots.count,
            "paths": roots.joined(separator: ",")
        ])

        // 脏数据刚清掉或尚未做过本人工作区发现 → 后台重扫一次并整体替换。
        let needsRediscover = !defaults.bool(forKey: Key.sanitizedPersonalOnly) || roots.isEmpty
        if needsRediscover {
            defaults.set(true, forKey: Key.sanitizedPersonalOnly)
            Task { @MainActor in
                let discovery = await Task.detached(priority: .userInitiated) {
                    ProjectRootDiscovery.discover()
                }.value
                _ = self.replaceDiscoveredRoots(discovery.roots)
                AppLog.warn("Projects", "启动后已按本人工作区重发现扫描根", [
                    "roots": discovery.roots.count,
                    "projects": discovery.projectCount,
                    "paths": discovery.roots.joined(separator: ",")
                ])
            }
        }
    }

    /// 是否可作为「本人工作区」扫描根：必须在当前用户家目录下，且不是工具链 / 卷别名。
    static func isPersonalWorkspaceRoot(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return false }
        // Volumes 别名、错误拼接的 Macintosh HD~
        if raw.contains("/Volumes/") || raw.contains("Macintosh HD") { return false }

        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.contains("/Volumes/") { return false }
        guard expanded.hasPrefix(home + "/") else { return false }

        let lower = expanded.lowercased()
        let junkFragments = [
            "/opt/homebrew", "/homebrew/", "/cellar/",
            "/private/tmp", "/tmp/",
            "/flutter/packages/", "/flutter/examples/", "/flutter/dev/",
            "/.pub-cache/", "/cocoapods", "/site-packages/", "/gems/"
        ]
        if junkFragments.contains(where: { lower.contains($0) }) { return false }

        let rel = String(expanded.dropFirst(home.count + 1))
        guard let top = rel.split(separator: "/").first.map(String.init), !top.isEmpty else {
            return false
        }
        let topLower = top.lowercased()
        if top.hasPrefix(".") { return false }
        if topLower == "flutter" || topLower.hasPrefix("flutter_") || topLower.hasPrefix("flutter-") {
            return false
        }
        if top.hasPrefix("CocoaPods") { return false }
        if ["library", "movies", "music", "pictures", "public", "applications",
            "downloads", "desktop", "documents", "go", "emsdk"].contains(topLower) {
            return false
        }

        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
    }

    private static func samePath(_ a: String, _ b: String) -> Bool {
        (a as NSString).expandingTildeInPath
            == (b as NSString).expandingTildeInPath
    }

    func addRoot(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let tilde = expanded.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        guard !roots.contains(where: {
            ($0 as NSString).expandingTildeInPath == expanded
        }) else { return }
        roots.append(tilde)
    }

    @discardableResult
    func mergeDiscoveredRoots(_ paths: [String]) -> Int {
        var next = roots
        var added = 0
        for path in paths where Self.isPersonalWorkspaceRoot(path) {
            let expanded = (path as NSString).expandingTildeInPath
            let tilde = expanded.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            guard !next.contains(where: {
                ($0 as NSString).expandingTildeInPath == expanded
            }) else { continue }
            next.append(tilde)
            added += 1
        }
        if added > 0 { roots = next }
        return added
    }

    @discardableResult
    func replaceDiscoveredRoots(_ paths: [String]) -> Int {
        let normalized = paths
            .filter(Self.isPersonalWorkspaceRoot)
            .map { path -> String in
                let expanded = (path as NSString).expandingTildeInPath
                return expanded.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
        let unique = Array(Set(normalized)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let before = Set(roots.map { ($0 as NSString).expandingTildeInPath })
        let added = unique.reduce(0) { partial, path in
            let expanded = (path as NSString).expandingTildeInPath
            return partial + (before.contains(expanded) ? 0 : 1)
        }
        roots = unique
        AppLog.warn("Projects", "已用发现结果替换扫描根", [
            "before": before.count,
            "after": unique.count,
            "added": added,
            "paths": unique.joined(separator: ",")
        ])
        return added
    }

    func removeRoot(_ path: String) {
        roots.removeAll {
            ($0 as NSString).expandingTildeInPath == (path as NSString).expandingTildeInPath
        }
    }
}
