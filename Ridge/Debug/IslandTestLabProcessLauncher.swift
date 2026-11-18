#if DEBUG
import Foundation

/// 一键拉起短生命周期样例进程 / 可选 Docker 容器，供控制台监视后测结束 tip。
@MainActor
enum IslandTestLabProcessLauncher {
    struct Launched: Equatable {
        let pid: Int32
        let label: String
        let kind: String
    }

    /// `/bin/sleep N`；返回 pid。
    static func launchSleep(seconds: Int = 12) throws -> Launched {
        let sec = min(max(seconds, 3), 120)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["\(sec)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        let launched = Launched(pid: pid, label: "sleep \(sec)s", kind: "process")
        AppLog.info("TestLab", "已启动样例进程", ["pid": pid, "seconds": sec])
        return launched
    }

    /// 若本机有 docker：`docker run --rm alpine sleep N`。
    static func launchDockerSleep(seconds: Int = 15) throws -> Launched {
        let sec = min(max(seconds, 5), 120)
        guard FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker")
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/docker")
            || FileManager.default.isExecutableFile(atPath: "/usr/bin/docker")
        else {
            throw LaunchError.dockerMissing
        }
        let dockerPath: String = {
            for path in ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "/usr/bin/docker"] {
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
            return "docker"
        }()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["run", "--rm", "--name", "ridge-lab-\(Int(Date().timeIntervalSince1970))", "alpine", "sleep", "\(sec)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        let launched = Launched(pid: pid, label: "docker alpine sleep \(sec)s", kind: "container")
        AppLog.info("TestLab", "已启动样例容器进程", ["pid": pid, "seconds": sec])
        return launched
    }

    enum LaunchError: LocalizedError {
        case dockerMissing

        var errorDescription: String? {
            switch self {
            case .dockerMissing: return L10n.TestLab.processDockerMissing
            }
        }
    }
}
#endif
