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

/// 下载临时后缀与成品路径解析（无隔离，供 Session / 单测共用）。
enum DownloadPathLogic {
    static let tempSuffixes = [
        ".crdownload",
        ".download",
        ".part",
        ".partial",
        ".opdownload",
        ".qqdownload",
        ".qbd",
        ".xltd",
        ".baiduyun",
        ".td",
        ".downloading",
    ]

    static func matchedTempSuffix(_ name: String) -> String? {
        let lower = name.lowercased()
        for suffix in tempSuffixes where lower.hasSuffix(suffix) {
            return String(name.suffix(suffix.count))
        }
        return nil
    }

    /// Chrome / Edge 等：英文 `Unconfirmed …` 与中文「未确认 …」均视为无名临时件。
    static func isUnconfirmedTempBase(_ stripped: String) -> Bool {
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("unconfirmed") { return true }
        if trimmed.hasPrefix("未确认") { return true }
        return false
    }

    /// 去掉 ` (N)` 序号后的基名，便于用上次同系列成品估总长。
    static func canonicalBaseName(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        var stem = url.deletingPathExtension().lastPathComponent
        if let regex = try? NSRegularExpression(pattern: #" \(\d+\)$"#),
           let match = regex.firstMatch(
               in: stem,
               range: NSRange(stem.startIndex..., in: stem)
           ),
           let range = Range(match.range, in: stem) {
            stem.removeSubrange(range)
        }
        if ext.isEmpty { return stem }
        return stem + "." + ext
    }

    /// 优先 preferred（须是「新写出」的成品）→ 同名 → 短窗内最新非临时文件。
    /// `notBefore`：忽略早于该时刻的同名旧文件，避免 Chrome 下到 `foo (5).dmg` 却命中旧 `foo.dmg`。
    static func resolveFinalURL(
        preferredPath: String?,
        displayName: String?,
        placeholderName: String,
        directory: URL,
        entries: [URL],
        recentWindow: TimeInterval,
        now: Date = Date(),
        notBefore: Date? = nil
    ) -> URL? {
        let floor = notBefore ?? now.addingTimeInterval(-recentWindow)

        func isFreshFinished(_ url: URL) -> Bool {
            guard matchedTempSuffix(url.lastPathComponent) == nil else { return false }
            let vals = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .creationDateKey,
            ])
            let stamp = vals?.contentModificationDate
                ?? vals?.creationDate
                ?? .distantPast
            return stamp >= floor
        }

        if let preferredPath,
           preferredPath.isEmpty == false,
           FileManager.default.fileExists(atPath: preferredPath) {
            let url = URL(fileURLWithPath: preferredPath)
            if isFreshFinished(url) {
                return url
            }
        }

        if let displayName,
           !displayName.isEmpty,
           displayName != placeholderName,
           !isUnconfirmedTempBase(displayName) {
            let candidate = directory.appendingPathComponent(displayName)
            if FileManager.default.fileExists(atPath: candidate.path),
               isFreshFinished(candidate) {
                return candidate
            }
        }

        var best: (url: URL, date: Date)?
        for url in entries {
            let name = url.lastPathComponent
            if matchedTempSuffix(name) != nil { continue }
            if name == ".DS_Store" || name == ".localized" { continue }
            let vals = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .creationDateKey,
            ])
            let stamp = vals?.contentModificationDate
                ?? vals?.creationDate
                ?? .distantPast
            guard stamp >= floor else { continue }
            guard now.timeIntervalSince(stamp) <= recentWindow else { continue }
            if best == nil || stamp > best!.date {
                best = (url, stamp)
            }
        }
        return best?.url
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
