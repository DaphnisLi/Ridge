import Foundation

/// 在用户指定的根目录下扫描可识别项目。
enum ProjectCatalog {
    private static let markers: [(file: String, kind: String)] = [
        ("package.json", "node"),
        ("pnpm-workspace.yaml", "node"),
        ("Cargo.toml", "rust"),
        ("go.mod", "go"),
        ("Package.swift", "swift"),
        ("project.yml", "xcode"),
        ("pyproject.toml", "python"),
        ("requirements.txt", "python"),
        ("Gemfile", "ruby"),
        ("pom.xml", "java"),
        ("build.gradle", "gradle"),
        ("build.gradle.kts", "gradle"),
        ("composer.json", "php")
    ]

    static func scan(roots: [String]) -> [ScannedProject] {
        var found: [String: ScannedProject] = [:]
        let fm = FileManager.default
        for root in roots {
            let expanded = (root as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
                AppLog.debug("Projects", "根目录不存在，跳过", ["root": expanded])
                continue
            }
            // 深度 6：覆盖 monorepo / packages/* 等常见结构；命中项目即停，并跳过依赖与构建目录。
            scanDirectory(expanded, depth: 0, maxDepth: 6, into: &found)
        }
        let list = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        AppLog.info("Projects", "项目扫描完成", [
            "roots": roots.count,
            "projects": list.count,
            "maxDepth": 6,
            "names": list.prefix(8).map(\.name).joined(separator: ",")
        ])
        return list
    }

    private static let skipDirectoryNames: Set<String> = [
        "node_modules", "target", "dist", "build", ".git", "Pods", "vendor",
        "DerivedData", ".build", ".next", ".turbo", ".cache", "__pycache__",
        "coverage", ".venv", "venv", "Carthage"
    ]

    private static func scanDirectory(
        _ path: String,
        depth: Int,
        maxDepth: Int,
        into found: inout [String: ScannedProject]
    ) {
        if found[path] != nil { return }
        if let project = identify(at: path) {
            found[path] = project
            return
        }
        guard depth < maxDepth else { return }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: path) else { return }
        for name in children {
            if name.hasPrefix(".") { continue }
            if skipDirectoryNames.contains(name) { continue }
            let child = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
            scanDirectory(child, depth: depth + 1, maxDepth: maxDepth, into: &found)
        }
    }

    private static func identify(at path: String) -> ScannedProject? {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        for marker in markers {
            let file = (path as NSString).appendingPathComponent(marker.file)
            if fm.fileExists(atPath: file) {
                return ScannedProject(path: path, name: name, kind: marker.kind)
            }
        }
        // Xcode：目录内有 *.xcodeproj
        if let kids = try? fm.contentsOfDirectory(atPath: path),
           kids.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            return ScannedProject(path: path, name: name, kind: "xcode")
        }
        return nil
    }
}
