import Combine
import Foundation

/// 项目释放模块偏好：扫描根目录。
@MainActor
final class ProjectSettings: ObservableObject {
    static let shared = ProjectSettings()

    private enum Key {
        static let roots = "projects.roots.v1"
    }

    @Published var roots: [String] {
        didSet {
            UserDefaults.standard.set(roots, forKey: Key.roots)
            AppLog.info("Projects", "已更新项目根目录", ["count": roots.count])
            guard isReady else { return }
            ProjectReleaseSession.shared.refresh(reason: "rootsChanged")
        }
    }

    /// 避免 init 赋值 roots 时反向拉起 Session。
    private var isReady = false

    private init() {
        let stored = UserDefaults.standard.array(forKey: Key.roots) as? [String]
        if let stored, !stored.isEmpty {
            roots = stored
        } else {
            // 默认父目录；立刻落盘，方便排查「根目录未写入」问题。
            roots = ["~/project", "~/code", "~/Developer", "~/Projects"]
            UserDefaults.standard.set(roots, forKey: Key.roots)
        }
        isReady = true
        AppLog.info("Projects", "已加载项目设置", [
            "roots": roots.count,
            "paths": roots.joined(separator: ",")
        ])
    }

    func addRoot(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let tilde = expanded.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        guard !roots.contains(where: {
            ($0 as NSString).expandingTildeInPath == expanded
        }) else { return }
        roots.append(tilde)
    }

    func removeRoot(_ path: String) {
        roots.removeAll {
            ($0 as NSString).expandingTildeInPath == (path as NSString).expandingTildeInPath
        }
    }
}
