import Foundation

/// 扫描到的本地项目（由 package.json / Cargo.toml 等识别）。
struct ScannedProject: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let kind: String
}

/// 归到某项目下的一条运行时占用。
struct ProjectRuntimeItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case process
        case container
        case orphanPort
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let pid: Int32?
    let containerID: String?
    let ports: [Int]
    let cpuPercent: Double
    let memoryBytes: UInt64
    /// 进程真实启动时间（仅 process；容器为 nil）。
    let startedAt: Date?
    /// 仅项目归属的进程 / 容器可释放；孤儿端口不可杀。
    let canRelease: Bool
}

struct ProjectRuntimeGroup: Identifiable, Hashable {
    let id: String
    let project: ScannedProject?
    /// `nil` 项目 = 未归属（只展示）。
    let items: [ProjectRuntimeItem]
    let totalCPU: Double
    let totalMemory: UInt64
    var canRelease: Bool { items.contains(where: \.canRelease) }
}

struct ProjectWatchTarget: Identifiable, Hashable {
    let id: String
    let pid: Int32
    let label: String
    let projectName: String
    /// 进程启动时间（非点击「监视」的时间）。
    let startedAt: Date
    /// 发现的日志文件路径（stdout/stderr 重定向）。
    let logPath: String?
    /// 最近一次采样的常驻内存（RSS）；进程死后无法再查，结束前持续刷新。
    var lastMemoryBytes: UInt64
    /// 监视期间观测到的峰值 RSS。
    var peakMemoryBytes: UInt64
}

/// 监视结束时在岛上 / 控制台展示的结果。
struct ProjectWatchEndedNotice: Identifiable, Hashable {
    let id: String
    let projectName: String
    let label: String
    let message: String
    let endedAt: Date
    let outcome: ProjectWatchOutcome
    let logPath: String?
    /// 监视期间峰值内存；0 表示未知。
    let peakMemoryBytes: UInt64
    /// 进程从启动到结束的时长；0 表示未知。
    let durationSeconds: TimeInterval
}
