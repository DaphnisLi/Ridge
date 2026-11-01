import AppKit
import Darwin
import Foundation

/// 把 CoreAudio / 辅助进程解析成「用户认识的宿主 App」。
///
/// 规则（对所有 App 一视同仁，不写个别品牌特例）：
/// 1. 进程路径上若嵌套多个 `.app`，取**最外层**且非 Helper 的那个；
/// 2. bundle id 带 `.helper` / `.renderer` 等后缀时，逐级剥到能被 NSWorkspace 认到的宿主；
/// 3. 图标与显示名**只**来自宿主 `.app`，不用 Helper 自己的图标。
enum SoundHostAppResolver {
    struct Identity: Equatable {
        /// 宿主 bundle id（优先）；找不到宿主时退回进程 bundle id。
        let bundleID: String?
        let name: String
        let icon: NSImage?
        /// 宿主 .app 路径，便于日志。
        let hostAppURL: URL?
    }

    static func resolve(pid: pid_t, processBundleID: String?) -> Identity {
        let running = NSRunningApplication(processIdentifier: pid)
        let hostURL = resolveHostAppURL(pid: pid, processBundleID: processBundleID, running: running)
        let hostBundleID = bundleID(at: hostURL) ?? parentBundleID(from: processBundleID)
        let name = displayName(hostURL: hostURL, hostBundleID: hostBundleID, running: running, processBundleID: processBundleID, pid: pid)
        let icon = hostURL.map { NSWorkspace.shared.icon(forFile: $0.path) }.flatMap { iconIsUsable($0) ? $0 : nil }

        if icon == nil {
            AppLog.debug("Sound", "宿主图标解析失败", [
                "pid": pid,
                "processBundle": processBundleID ?? "nil",
                "hostBundle": hostBundleID ?? "nil",
                "host": hostURL?.path ?? "nil"
            ])
        } else if let hostURL, isNestedOrHelperBundle(hostURL) {
            AppLog.debug("Sound", "宿主仍像辅助包，请检查", ["host": hostURL.path])
        }

        return Identity(
            bundleID: hostBundleID ?? processBundleID,
            name: name,
            icon: icon,
            hostAppURL: hostURL
        )
    }

    // MARK: - Host URL

    private static func resolveHostAppURL(
        pid: pid_t,
        processBundleID: String?,
        running: NSRunningApplication?
    ) -> URL? {
        var candidates: [URL] = []

        // A. bundle id 剥后缀 → Workspace 查找（最稳：com.soda.music.helper → com.soda.music）
        for bid in bundleIDSearchList(processBundleID) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                candidates.append(url)
            }
        }

        // B. 进程 bundleURL / 可执行路径向上收集所有 .app
        if let url = running?.bundleURL {
            candidates.append(contentsOf: allAppBundles(alongPath: url))
        }
        if let path = processPath(pid: pid) {
            candidates.append(contentsOf: allAppBundles(alongPath: URL(fileURLWithPath: path)))
        }

        return pickBestHost(from: candidates)
    }

    /// 候选里选宿主：非 Helper，且路径上尽量外层（组件数更少 = 更靠外）。
    private static func pickBestHost(from urls: [URL]) -> URL? {
        let unique = dedupe(urls)
        let hosts = unique.filter { !isNestedOrHelperBundle($0) }
        let pool = hosts.isEmpty ? unique.filter { !isHelperAppBundle($0) } : hosts
        let finalPool = pool.isEmpty ? unique : pool
        return finalPool.min { lhs, rhs in
            pathRank(lhs) < pathRank(rhs)
        }
    }

    /// 路径越浅（越靠近 /Applications/Foo.app）优先级越高。
    private static func pathRank(_ url: URL) -> (Int, Int, String) {
        let standardized = url.standardizedFileURL.path
        let components = url.pathComponents.count
        let nestedPenalty = standardized.contains(".app/Contents/") ? 1 : 0
        return (nestedPenalty, components, standardized)
    }

    private static func allAppBundles(alongPath url: URL) -> [URL] {
        var current = url.standardizedFileURL
        var found: [URL] = []
        for _ in 0..<12 {
            if current.pathExtension.lowercased() == "app" {
                found.append(current)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return found
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url.standardizedFileURL)
            }
        }
        return result
    }

    // MARK: - Bundle ID

    private static func bundleIDSearchList(_ processBundleID: String?) -> [String] {
        guard let processBundleID, !processBundleID.isEmpty else { return [] }
        var list: [String] = []
        for candidate in parentBundleIDCandidates(processBundleID) {
            if !list.contains(candidate) { list.append(candidate) }
        }
        if !isHelperBundleID(processBundleID), !list.contains(processBundleID) {
            list.append(processBundleID)
        }
        return list
    }

    private static func parentBundleID(from processBundleID: String?) -> String? {
        guard let processBundleID else { return nil }
        return parentBundleIDCandidates(processBundleID).first
    }

    /// com.foo.bar.helper.renderer → com.foo.bar.helper → com.foo.bar …
    static func parentBundleIDCandidates(_ bundleID: String) -> [String] {
        var results: [String] = []
        var current = bundleID

        // 先按已知辅助后缀整段剥。
        let suffixes = [
            ".helper.renderer", ".helper.gpu", ".helper.plugin", ".helper.alerter",
            ".helper", ".renderer", ".gpu", ".plugin", ".loginhelper", ".login-helper"
        ]
        var stripped = true
        while stripped {
            stripped = false
            for suffix in suffixes {
                if current.lowercased().hasSuffix(suffix) {
                    current = String(current.dropLast(suffix.count))
                    if !current.isEmpty, !results.contains(current) {
                        results.append(current)
                    }
                    stripped = true
                    break
                }
            }
        }

        // 再逐段去掉末尾（兼容未知后缀）。
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count > 2 {
            let last = parts.last?.lowercased() ?? ""
            let looksAuxiliary = last.hasPrefix("helper")
                || last == "renderer" || last == "gpu" || last == "plugin"
                || last == "alerter" || last.contains("helper")
            parts.removeLast()
            let candidate = parts.joined(separator: ".")
            if looksAuxiliary || isHelperBundleID(bundleID) {
                if !results.contains(candidate) {
                    results.append(candidate)
                }
            } else {
                break
            }
        }
        return results
    }

    private static func bundleID(at url: URL?) -> String? {
        guard let url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
            ?? bundleIDFromInfoPlist(url)
    }

    private static func bundleIDFromInfoPlist(_ appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    // MARK: - Naming

    private static func displayName(
        hostURL: URL?,
        hostBundleID: String?,
        running: NSRunningApplication?,
        processBundleID: String?,
        pid: pid_t
    ) -> String {
        if let hostURL {
            let name = FileManager.default.displayName(atPath: hostURL.path)
            if !name.isEmpty, !isHelperDisplayName(name) { return name }
        }
        if let hostBundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hostBundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            if !name.isEmpty { return name }
        }
        if let runningName = running?.localizedName, !isHelperDisplayName(runningName) {
            return runningName
        }
        return processBundleID ?? "PID \(pid)"
    }

    // MARK: - Helper detection

    /// 嵌在其它 .app 的 Contents 里，或名字像 Helper → 不是宿主。
    private static func isNestedOrHelperBundle(_ url: URL) -> Bool {
        if isHelperAppBundle(url) { return true }
        return url.standardizedFileURL.path.contains(".app/Contents/")
    }

    private static func isHelperAppBundle(_ url: URL) -> Bool {
        isHelperDisplayName(url.deletingPathExtension().lastPathComponent)
            || isHelperBundleID(Bundle(url: url)?.bundleIdentifier ?? "")
    }

    private static func isHelperBundleID(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        let lower = bundleID.lowercased()
        if lower.contains(".helper") { return true }
        if lower.hasSuffix(".renderer") || lower.hasSuffix(".gpu") || lower.hasSuffix(".plugin") {
            return true
        }
        return false
    }

    private static func isHelperDisplayName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("helper") { return true }
        if lower.contains("(gpu)") || lower.contains("(renderer)") || lower.contains("(plugin)") {
            return true
        }
        if lower.contains(" login") { return true }
        return false
    }

    // MARK: - System

    private static func processPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard written > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func iconIsUsable(_ icon: NSImage) -> Bool {
        icon.size.width >= 1 && icon.size.height >= 1
    }
}
