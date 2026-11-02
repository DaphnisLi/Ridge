import Foundation

/// 一次系统资源快照（轻量指标周期采样）。
struct ResourceSnapshot: Equatable {
    var sampledAt: Date = .distantPast
    /// 物理内存已用字节（近似）。
    var ramUsedBytes: UInt64 = 0
    var ramTotalBytes: UInt64 = 0
    var ramPercent: Double = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var swapPercent: Double = 0
    /// 整机 CPU 占用 0…100。
    var cpuPercent: Double = 0
    /// 摄氏度；读不到则为 nil（UI 隐藏）。
    var cpuCelsius: Double? = nil
    var topApps: [ResourceAppUsage] = []
    /// 纳入监控聚合的进程数（过滤内核杂项后）。
    var monitoredProcessCount: Int = 0
    /// `ps` 枚举到的进程总量（含系统内核托管）。
    var kernelProcessCount: Int = 0
}

struct ResourceAppUsage: Identifiable, Equatable, Hashable {
    var id: String { bundleID.isEmpty ? "pid:\(mainPID)" : bundleID }
    var bundleID: String
    var name: String
    var mainPID: Int32
    var memoryBytes: UInt64
    /// 整机 CPU 占比 0…100（非单核 %CPU）。
    var cpuPercent: Double
    var childCount: Int
    /// 可展开的子进程；空则 UI 不显示展开。
    var children: [ResourceChildProcess]
}

struct ResourceChildProcess: Identifiable, Equatable, Hashable {
    var id: String { "\(pid)" }
    var pid: Int32
    var title: String
    var memoryBytes: UInt64
    /// 整机 CPU 占比 0…100。
    var cpuPercent: Double
    var canKill: Bool
}

enum ResourceKillFailure: Equatable {
    case notFound
    case protected
    case permissionDenied
    case other(String)

    var message: String {
        switch self {
        case .notFound: return L10n.ResourceMonitor.killNotFound
        case .protected: return L10n.ResourceMonitor.killProtected
        case .permissionDenied: return L10n.ResourceMonitor.killPermissionDenied
        case .other(let detail): return L10n.ResourceMonitor.killOther(detail)
        }
    }
}

/// 按日聚合：击键 + 当日峰值 RAM 档位（0…4）。
struct ResourceDayAggregate: Codable, Equatable {
    var dayKey: String
    var keystrokes: Int
    var peakRamBand: Int
    var appSwitches: Int
}

struct ResourceFocusSlice: Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var seconds: TimeInterval
    var colorIndex: Int
}

/// 今日 RAM 波形一点：时刻 + 已用 GB + 占用百分比。
struct ResourceRAMSample: Equatable {
    var at: Date
    var usedGB: Double
    var percent: Double
}

struct ResourceRAMPressureNotice: Hashable, Identifiable {
    let id: String
    let ramUsedBytes: UInt64
    let ramPercent: Double
    let topAppName: String
    let topAppMemoryBytes: UInt64
}
