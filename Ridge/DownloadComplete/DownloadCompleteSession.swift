import AppKit
import Combine
import Foundation

/// 监视下载目录：临时件 → 进行中估速上岛；消失且成品 size 稳定 → 完成态。
@MainActor
final class DownloadCompleteSession: ObservableObject {
    static let shared = DownloadCompleteSession()

    @Published private(set) var pending: DownloadCompleteItem?

    private var started = false
    private var directoryFD: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var stabilityTasks: [String: Task<Void, Never>] = [:]
    /// 临时件路径 → 采样状态。
    private var tracks: [String: TempTrack] = [:]
    /// 短窗去抖：规范化路径 → 上次完成时刻。
    private var recentCompleted: [String: Date] = [:]
    private let stabilityNanoseconds: UInt64 = 700_000_000
    private let dedupeWindow: TimeInterval = 45
    /// 速度 EMA；越大越跟瞬时。
    private let speedEmaAlpha: Double = 0.35

    /// Chromium 系（Chrome / Edge / Brave / Arc / QQ / 360 等）+ Safari / Firefox / Opera。
    private static let tempSuffixes = [
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

    private struct TempTrack {
        var finalPath: String
        var displayName: String
        var lastBytes: Int64
        var lastSampleAt: Date
        var emaSpeed: Double
        var sampleCount: Int
    }

    private init() {}

    private var tipEnabled: Bool {
        WidgetSettings.shared.isEnabled(DownloadCompleteTipWidget.manifest.id)
    }

    /// 有进行中或未处理完成项且开关开着 → 岛上常驻。
    var showsCompactStandby: Bool {
        tipEnabled && pending != nil
    }

    var downloadsDirectoryURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    func start() {
        guard !started else {
            AppLog.debug("Download", "会话已在跑，跳过重复 start")
            return
        }
        started = true
        openWatch()
        // 进行中要估速：略密轮询；无活动时开销仍小。
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanDirectory(reason: "poll")
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
        scanDirectory(reason: "start")
        AppLog.warn("Download", "下载会话已启动", [
            "tipOn": tipEnabled,
            "dir": downloadsDirectoryURL.path
        ])
        notifyResidentsChanged()
    }

    func stop() {
        guard started else { return }
        closeWatch()
        pollTimer?.invalidate()
        pollTimer = nil
        for (_, task) in stabilityTasks { task.cancel() }
        stabilityTasks.removeAll()
        tracks.removeAll()
        started = false
        if pending != nil {
            pending = nil
            AppLog.warn("Download", "会话停止，已清下载常驻")
        }
        notifyResidentsChanged()
        AppLog.warn("Download", "下载会话已停止")
    }

    /// 设置 / 测试台：挂一条假完成项。
    func presentSample(fileName: String = "Report.pdf") {
        let path = downloadsDirectoryURL.appendingPathComponent(fileName).path
        pending = DownloadCompleteItem(
            path: path,
            fileName: fileName,
            phase: .completed,
            bytesReceived: 1_048_576,
            totalBytes: 1_048_576
        )
        AppLog.warn("Download", "已挂假下载完成样张", ["name": fileName])
        notifyResidentsChanged()
    }

    /// 测试台：挂进行中样张（带估速，无总长 → UI 不画假进度）。
    func presentDownloadingSample(
        fileName: String = "Archive.zip",
        speedBytesPerSecond: Double = 2_400_000
    ) {
        let path = downloadsDirectoryURL
            .appendingPathComponent(fileName + ".crdownload")
            .path
        pending = DownloadCompleteItem(
            path: path,
            fileName: fileName,
            phase: .downloading,
            bytesReceived: 12_000_000,
            totalBytes: nil,
            speedBytesPerSecond: speedBytesPerSecond
        )
        AppLog.warn("Download", "已挂假下载进行中样张", [
            "name": fileName,
            "speed": Int(speedBytesPerSecond)
        ])
        notifyResidentsChanged()
    }

    func clearPending(reason: String) {
        guard pending != nil else { return }
        pending = nil
        AppLog.info("Download", "已撤下载常驻", ["reason": reason])
        notifyResidentsChanged()
    }

    /// 点按岛：进行中 → Reveal 不撤；完成后按设置打开/Reveal 并撤。
    @discardableResult
    func handleClick() -> Bool {
        guard let item = pending else { return false }
        let url = URL(fileURLWithPath: item.path)
        if item.phase == .downloading {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            AppLog.warn("Download", "用户点按进行中下载岛 → Reveal", [
                "name": item.fileName
            ])
            return true
        }

        let action = DownloadCompleteSettings.shared.clickAction
        var ok = false
        switch action {
        case .openWithDefaultApp:
            ok = NSWorkspace.shared.open(url)
            if !ok {
                AppLog.warn("Download", "默认 App 打开失败，回退 Reveal", ["path": item.fileName])
                NSWorkspace.shared.activateFileViewerSelecting([url])
                ok = true
            }
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            ok = true
        }
        AppLog.warn("Download", "用户点按下载完成岛", [
            "action": action.rawValue,
            "ok": ok,
            "name": item.fileName
        ])
        if ok {
            clearPending(reason: "click:\(action.rawValue)")
        }
        return ok
    }

    // MARK: - Watch

    private func openWatch() {
        closeWatch()
        let path = downloadsDirectoryURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            AppLog.warn("Download", "无法监视下载目录", ["path": path, "errno": errno])
            return
        }
        directoryFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: DispatchQueue.main
        )
        src.setEventHandler { [weak self] in
            self?.scanDirectory(reason: "fsEvent")
        }
        src.setCancelHandler { [weak self] in
            if let self, self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }
        source = src
        src.resume()
        AppLog.debug("Download", "已监视下载目录", ["path": path])
    }

    private func closeWatch() {
        source?.cancel()
        source = nil
        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
        }
    }

    private func scanDirectory(reason: String) {
        guard tipEnabled else { return }
        let dir = downloadsDirectoryURL
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            AppLog.debug("Download", "列目录失败", ["reason": reason])
            return
        }

        let now = Date()
        var seenTemp = Set<String>()
        var bestTemp: (path: String, mtime: Date)?

        for url in entries {
            let name = url.lastPathComponent
            guard let temp = Self.matchedTempSuffix(name) else { continue }
            let tempPath = url.path
            seenTemp.insert(tempPath)

            let stripped = String(name.dropLast(temp.count))
            // Chrome Unconfirmed 123456.crdownload → 显示占位名，等真正 rename。
            let displayName: String = {
                if stripped.hasPrefix("Unconfirmed ") || stripped.isEmpty {
                    return L10n.DownloadComplete.downloadingPlaceholderName
                }
                return stripped
            }()
            let finalPath: String = {
                if stripped.hasPrefix("Unconfirmed ") || stripped.isEmpty {
                    return tempPath
                }
                return dir.appendingPathComponent(stripped).path
            }()

            let bytes = Self.byteCount(at: url)
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? now
            if bestTemp == nil || mtime > bestTemp!.mtime {
                bestTemp = (tempPath, mtime)
            }

            if var track = tracks[tempPath] {
                let dt = now.timeIntervalSince(track.lastSampleAt)
                if bytes >= 0, track.lastBytes >= 0, dt >= 0.25 {
                    let delta = Double(bytes - track.lastBytes)
                    if delta >= 0 {
                        let instant = delta / dt
                        track.emaSpeed = track.sampleCount == 0
                            ? instant
                            : track.emaSpeed * (1 - speedEmaAlpha) + instant * speedEmaAlpha
                        track.sampleCount += 1
                    }
                    track.lastBytes = bytes
                    track.lastSampleAt = now
                } else if bytes >= 0, track.lastBytes < 0 {
                    track.lastBytes = bytes
                    track.lastSampleAt = now
                }
                track.displayName = displayName
                track.finalPath = finalPath
                tracks[tempPath] = track
            } else {
                tracks[tempPath] = TempTrack(
                    finalPath: finalPath,
                    displayName: displayName,
                    lastBytes: bytes,
                    lastSampleAt: now,
                    emaSpeed: 0,
                    sampleCount: 0
                )
                AppLog.debug("Download", "见下载临时件", [
                    "temp": name,
                    "final": displayName,
                    "reason": reason
                ])
            }
        }

        // 临时件消失 → 校验成品并启动稳定窗。
        for (tempPath, track) in tracks {
            if seenTemp.contains(tempPath) { continue }
            tracks.removeValue(forKey: tempPath)
            let finalPath = track.finalPath
            // Unconfirmed 仅临时路径：消失时若无独立成品名，仍尝试同目录下最近新建文件较难；走 finalPath。
            if finalPath == tempPath {
                AppLog.debug("Download", "Unconfirmed 临时消失且无成品名，跳过", [
                    "reason": reason
                ])
                if pending?.phase == .downloading, pending?.path == tempPath {
                    clearPending(reason: "tempGoneNoFinal")
                }
                continue
            }
            scheduleStabilityCheck(finalPath: finalPath, reason: reason)
        }

        // 进行中：挂最新临时件（按 mtime）；完成后若用户未处理则不被进行中顶掉——
        // 产品：同时只挂一条「最新活动」；新下载替换未点完成项。
        if let best = bestTemp, let track = tracks[best.path] {
            let speed: Double? = track.sampleCount >= 2 && track.emaSpeed >= DownloadTransferFormatting.minimumDisplaySpeed
                ? track.emaSpeed
                : nil
            let next = DownloadCompleteItem(
                path: best.path,
                fileName: track.displayName,
                phase: .downloading,
                bytesReceived: track.lastBytes >= 0 ? track.lastBytes : nil,
                totalBytes: nil,
                speedBytesPerSecond: speed,
                updatedAt: now
            )
            let identityChanged = pending?.path != next.path
                || pending?.phase != .downloading
                || pending?.fileName != next.fileName
            pending = next
            if identityChanged {
                AppLog.info("Download", "下载进行中上岛", [
                    "name": next.fileName,
                    "bytes": next.bytesReceived ?? -1,
                    "speed": Int(speed ?? 0),
                    "reason": reason
                ])
                notifyResidentsChanged()
            }
        }
        // 临时都没了：保留当前完成态；进行中则等 stability 窗把态切到 completed。
    }

    private func scheduleStabilityCheck(finalPath: String, reason: String) {
        stabilityTasks[finalPath]?.cancel()
        let nano = stabilityNanoseconds
        stabilityTasks[finalPath] = Task { @MainActor in
            defer { stabilityTasks[finalPath] = nil }
            let url = URL(fileURLWithPath: finalPath)
            guard FileManager.default.fileExists(atPath: finalPath) else {
                AppLog.debug("Download", "临时消失但无成品", [
                    "path": url.lastPathComponent,
                    "reason": reason
                ])
                return
            }
            let size1 = Self.byteCount(at: url)
            try? await Task.sleep(nanoseconds: nano)
            guard !Task.isCancelled else { return }
            guard FileManager.default.fileExists(atPath: finalPath) else { return }
            let size2 = Self.byteCount(at: url)
            guard size1 >= 0, size1 == size2 else {
                AppLog.debug("Download", "成品 size 未稳，再等", [
                    "name": url.lastPathComponent,
                    "s1": size1,
                    "s2": size2
                ])
                scheduleStabilityCheck(finalPath: finalPath, reason: "restable")
                return
            }
            acceptCompleted(path: finalPath, bytes: size2, reason: reason)
        }
    }

    private func acceptCompleted(path: String, bytes: Int64, reason: String) {
        let key = path
        let now = Date()
        if let last = recentCompleted[key], now.timeIntervalSince(last) < dedupeWindow {
            AppLog.debug("Download", "同路径去抖，跳过", ["name": URL(fileURLWithPath: path).lastPathComponent])
            return
        }
        recentCompleted[key] = now
        pruneRecent(now: now)

        let item = DownloadCompleteItem(
            path: path,
            phase: .completed,
            bytesReceived: bytes >= 0 ? bytes : nil,
            totalBytes: bytes >= 0 ? bytes : nil,
            speedBytesPerSecond: nil,
            updatedAt: now,
            completedAt: now,
            sourceBundleID: Self.quarantineAgentBundleID(for: path)
        )
        pending = item
        AppLog.warn("Download", "下载完成，已挂常驻", [
            "name": item.fileName,
            "bytes": bytes,
            "reason": reason,
            "agent": item.sourceBundleID ?? ""
        ])
        notifyResidentsChanged()
    }

    private func pruneRecent(now: Date) {
        recentCompleted = recentCompleted.filter { now.timeIntervalSince($0.value) < dedupeWindow * 2 }
    }

    private func notifyResidentsChanged() {
        NotificationCenter.default.post(name: .downloadCompleteResidentsDidChange, object: nil)
        IslandNoticeCenter.shared.refreshResidentsFromDownload()
    }

    private static func matchedTempSuffix(_ name: String) -> String? {
        let lower = name.lowercased()
        for suffix in tempSuffixes where lower.hasSuffix(suffix) {
            return String(name.suffix(suffix.count))
        }
        return nil
    }

    /// 文件或 Safari `.download` 包的字节数；失败返回 -1。
    private static func byteCount(at url: URL) -> Int64 {
        guard let vals = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
        ]) else { return -1 }
        if vals.isDirectory == true {
            if let allocated = vals.totalFileAllocatedSize, allocated > 0 {
                return Int64(allocated)
            }
            return directoryByteCount(url)
        }
        if let size = vals.fileSize { return Int64(size) }
        if let allocated = vals.totalFileAllocatedSize { return Int64(allocated) }
        return -1
    }

    private static func directoryByteCount(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return -1 }
        var total: Int64 = 0
        var saw = false
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true,
                  let size = vals.fileSize
            else { continue }
            total += Int64(size)
            saw = true
        }
        return saw ? total : -1
    }

    /// 尽力读 quarantine；失败不挡完成。
    private static func quarantineAgentBundleID(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey]),
              let props = values.quarantineProperties,
              let agent = props["LSQuarantineAgentBundleIdentifierKey"] as? String,
              !agent.isEmpty
        else { return nil }
        return agent
    }
}

extension Notification.Name {
    static let downloadCompleteResidentsDidChange = Notification.Name("ridge.downloadComplete.residents")
}

/// 收起态是否应画下载待命小岛（被会议/音乐盖时仍可能 `showsCompactStandby`，但画面不露）。
enum DownloadCompactPresence {
    @MainActor
    static var isActive: Bool {
        DownloadCompleteSession.shared.showsCompactStandby
    }

    @MainActor
    static var isVisiblyShowingCompact: Bool {
        guard isActive else { return false }
        switch IslandNoticeCenter.shared.slots.resolvedLayout {
        case .fullDownload, .dual(left: .download, _):
            return true
        default:
            if IslandNoticeCenter.shared.slots.hasNoticePayload { return false }
            if MediaCompactPresence.isActive { return false }
            return true
        }
    }
}
