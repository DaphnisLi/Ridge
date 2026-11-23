import Foundation

/// 点按下载完成岛后的动作（仅完成后生效；进行中点按一律 Reveal）。
enum DownloadCompleteClickAction: String, CaseIterable, Identifiable {
    case openWithDefaultApp
    case revealInFinder

    var id: String { rawValue }
}

/// 下载岛会话阶段：进行中可估速；完成后可打开。
enum DownloadIslandPhase: String, Equatable, Hashable {
    case downloading
    case completed
}

/// 当前挂起的下载岛会话（同时最多一条；进行中或已完成）。
struct DownloadCompleteItem: Equatable, Hashable, Identifiable {
    var id: String { path }
    /// 进行中多为临时件路径；完成后为成品绝对路径。
    var path: String
    var fileName: String
    var phase: DownloadIslandPhase
    var bytesReceived: Int64?
    /// 文件系统路径通常拿不到总长；有值才画进度，否则退化图标。
    var totalBytes: Int64?
    /// 对临时件采样估出的字节/秒；不足置信度时为 nil → UI 退化图标。
    var speedBytesPerSecond: Double?
    var updatedAt: Date
    var completedAt: Date?
    /// 可选：来源浏览器 bundle（若能从 quarantine 读到）。
    var sourceBundleID: String?

    var isCompleted: Bool { phase == .completed }

    /// 有可信总长时才给进度 0…1；否则 nil（禁止假百分比）。
    var progressFraction: Double? {
        guard let total = totalBytes, total > 0,
              let got = bytesReceived, got >= 0
        else { return nil }
        return min(1, Double(got) / Double(total))
    }

    init(
        path: String,
        fileName: String? = nil,
        phase: DownloadIslandPhase = .completed,
        bytesReceived: Int64? = nil,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        sourceBundleID: String? = nil
    ) {
        self.path = path
        self.fileName = fileName ?? URL(fileURLWithPath: path).lastPathComponent
        self.phase = phase
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.updatedAt = updatedAt
        self.completedAt = completedAt ?? (phase == .completed ? updatedAt : nil)
        self.sourceBundleID = sourceBundleID
    }
}

/// 下载字节 / 速度文案（文件风格，便于岛面短展示）。
enum DownloadTransferFormatting {
    /// 低于此瞬时速度不展示，避免抖动成「0 KB/s」。
    static let minimumDisplaySpeed: Double = 512

    static func sizeText(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(0, bytes))
    }

    /// 有可信速度则 `"1.2 MB/s"`；否则 nil（UI 退化成图标）。
    static func speedText(bytesPerSecond: Double?) -> String? {
        guard let bps = bytesPerSecond, bps >= minimumDisplaySpeed else { return nil }
        return sizeText(bytes: Int64(bps.rounded())) + "/s"
    }
}
