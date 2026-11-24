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
    /// 进行中孤儿：临时已空后首次发现的时刻（用于兜底切完成态）。
    private var orphanDownloadingSince: Date?
    /// 最近完成成品的字节数（同系列 / 未确认下载用来估进度环总长）。
    private var lastCompletedBytesByBase: [String: Int64] = [:]
    private var lastCompletedBytesAny: Int64?
    /// 完成态约 3s 自动撤；悬停时不计时。
    private var completedDismissTask: Task<Void, Never>?
    /// 完成态驻留期间注册的全局快捷键（其它 App 前台也能命中，避免落到对方 ⌘O）。
    private var registeredOpenChord: HotKeyChord?
    private static let openHotKeyID = "builtin.downloadComplete.openTransient"
    private let completedAutoDismissNanoseconds =
        IslandNoticeAutoDismissPolicy.standardNanoseconds
    private let stabilityNanoseconds: UInt64 = 500_000_000
    private let missingFinalRetryNanoseconds: UInt64 = 300_000_000
    private let missingFinalMaxAttempts = 12
    private let orphanGrace: TimeInterval = 1.2
    private let recentFinalWindow: TimeInterval = 20
    private let dedupeWindow: TimeInterval = 45
    /// 速度 EMA；越大越跟瞬时。
    private let speedEmaAlpha: Double = 0.35

    private struct TempTrack {
        var finalPath: String?
        var displayName: String
        var lastBytes: Int64
        var lastSampleAt: Date
        var emaSpeed: Double
        var sampleCount: Int
        var isUnconfirmed: Bool
        /// 浏览器元数据或同系列上次完成估得的总长；未知则 nil。
        var totalBytes: Int64?
        var startedAt: Date
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
        seedPriorCompletedSizes()
        scanDirectory(reason: "start")
        AppLog.warn("Download", "下载会话已启动", [
            "tipOn": tipEnabled,
            "dir": downloadsDirectoryURL.path,
            "priorSizes": lastCompletedBytesByBase.count
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
        orphanDownloadingSince = nil
        cancelCompletedAutoDismiss()
        uninstallOpenShortcutMonitor()
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
        orphanDownloadingSince = nil
        AppLog.warn("Download", "已挂假下载完成样张", ["name": fileName])
        notifyResidentsChanged()
        beginCompletedPresentation()
    }

    /// 测试台：挂进行中样张（带估速 + 样张总长，便于验进度环）。
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
            totalBytes: 20_000_000,
            speedBytesPerSecond: speedBytesPerSecond
        )
        orphanDownloadingSince = nil
        AppLog.warn("Download", "已挂假下载进行中样张", [
            "name": fileName,
            "speed": Int(speedBytesPerSecond),
            "total": 20_000_000
        ])
        notifyResidentsChanged()
    }

    /// 测试台：把当前进行中样张立刻切到完成态（验收态切换）。
    func presentForceCompleteFromDownloading() {
        guard let item = pending, item.phase == .downloading else {
            presentSample()
            return
        }
        let finalName = item.fileName
        let path = downloadsDirectoryURL.appendingPathComponent(finalName).path
        acceptCompleted(
            path: path,
            fileName: finalName,
            bytes: item.bytesReceived ?? 0,
            reason: "testLabForceComplete"
        )
    }

    func clearPending(reason: String) {
        guard pending != nil else { return }
        pending = nil
        orphanDownloadingSince = nil
        cancelCompletedAutoDismiss()
        uninstallOpenShortcutMonitor()
        AppLog.warn("Download", "已撤下载常驻", ["reason": reason])
        notifyResidentsChanged()
    }

    /// 点按岛 / 「打开」按钮 / 设置快捷键：进行中 → Reveal 不撤；完成 → 按设置打开或访达选中后撤。
    @discardableResult
    func handleClick() -> Bool {
        guard let item = pending else { return false }
        if item.phase == .downloading {
            let url = URL(fileURLWithPath: item.path)
            if FileManager.default.fileExists(atPath: item.path) {
                revealInFinder(url)
            } else {
                NSWorkspace.shared.open(downloadsDirectoryURL)
            }
            IslandController.shared?.suppressHoverExpandAfterExternalOpen(
                reason: "downloadClick:downloadingReveal"
            )
            AppLog.warn("Download", "用户点按进行中下载岛 → Reveal", [
                "name": item.fileName
            ])
            return true
        }

        guard let url = resolvedCompletedFileURL(for: item) else {
            NSWorkspace.shared.open(downloadsDirectoryURL)
            AppLog.warn("Download", "完成态找不到成品，已打开下载文件夹", [
                "name": item.fileName,
                "path": item.path
            ])
            IslandController.shared?.suppressHoverExpandAfterExternalOpen(
                reason: "downloadClick:missingFile"
            )
            clearPending(reason: "click:missingFile")
            return true
        }

        let action = DownloadCompleteSettings.shared.clickAction
        var ok = false
        switch action {
        case .openWithDefaultApp:
            ok = openWithDefaultApp(url)
            if !ok {
                AppLog.warn("Download", "默认 App 打开失败，回退访达选中", [
                    "name": url.lastPathComponent
                ])
                ok = revealInFinder(url)
            }
        case .revealInFinder:
            ok = revealInFinder(url)
        }
        AppLog.warn("Download", "用户打开下载完成项", [
            "action": action.rawValue,
            "name": url.lastPathComponent,
            "path": url.path,
            "expected": item.fileName,
            "nameMatch": url.lastPathComponent == item.fileName,
            "ok": ok
        ])
        if ok {
            // 先抑悬停再撤 tip：否则伸手点访达/镜像窗时会掀开番茄等底层面板。
            IslandController.shared?.suppressHoverExpandAfterExternalOpen(
                reason: "downloadClick:\(action.rawValue)"
            )
            clearPending(reason: "click:\(action.rawValue)")
        }
        return ok
    }

    /// 设置改快捷开关时同步监听。
    func refreshOpenShortcutMonitor() {
        if pending?.phase == .completed,
           DownloadCompleteSettings.shared.keyboardShortcutEnabled {
            installOpenShortcutMonitorIfNeeded()
        } else {
            uninstallOpenShortcutMonitor()
        }
    }

    /// 优先 `Downloads/<fileName>`，避免 path 指到旧同名或失效路径。
    private func resolvedCompletedFileURL(for item: DownloadCompleteItem) -> URL? {
        let fm = FileManager.default
        let placeholder = L10n.DownloadComplete.downloadingPlaceholderName

        if item.fileName != placeholder,
           item.fileName.isEmpty == false,
           DownloadPathLogic.matchedTempSuffix(item.fileName) == nil,
           !DownloadPathLogic.isUnconfirmedTempBase(item.fileName) {
            let byName = downloadsDirectoryURL.appendingPathComponent(item.fileName)
            if fm.fileExists(atPath: byName.path) {
                return byName
            }
        }

        let primary = URL(fileURLWithPath: item.path)
        if fm.fileExists(atPath: primary.path),
           DownloadPathLogic.matchedTempSuffix(primary.lastPathComponent) == nil,
           primary.lastPathComponent == item.fileName
            || item.fileName == placeholder {
            return primary
        }

        guard let entries = try? fm.contentsOfDirectory(
            at: downloadsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        if let url = DownloadPathLogic.resolveFinalURL(
            preferredPath: nil,
            displayName: item.fileName == placeholder ? nil : item.fileName,
            placeholderName: placeholder,
            directory: downloadsDirectoryURL,
            entries: entries,
            recentWindow: recentFinalWindow,
            notBefore: item.completedAt?.addingTimeInterval(-5)
        ) {
            AppLog.warn("Download", "完成态按短窗重解析成品", [
                "name": url.lastPathComponent,
                "expected": item.fileName
            ])
            return url
        }
        return nil
    }

    /// 用默认 App 打开成品；镜像类走访达选中，避免系统弹出怪异「打开」面板。
    @discardableResult
    private func openWithDefaultApp(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if Self.diskImageExtensions.contains(ext) {
            AppLog.warn("Download", "磁盘镜像改走访达选中，避免误开镜像面板", [
                "name": url.lastPathComponent,
                "ext": ext
            ])
            return revealInFinder(url)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error {
                AppLog.warn("Download", "OpenConfiguration 打开失败", [
                    "name": url.lastPathComponent,
                    "error": error.localizedDescription
                ])
            }
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    private func revealInFinder(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        // 优先 activateFileViewerSelecting：对 .dmg 等不会误触发镜像「打开」面板。
        NSWorkspace.shared.activateFileViewerSelecting([url])
        AppLog.warn("Download", "已在访达中选中", [
            "name": url.lastPathComponent,
            "path": url.path
        ])
        return true
    }

    private static let diskImageExtensions: Set<String> = ["dmg", "iso", "img", "toast"]

    private func scheduleCompletedAutoDismiss() {
        cancelCompletedAutoDismiss()
        let nanos = completedAutoDismissNanoseconds
        completedDismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var elapsed: UInt64 = 0
            let poll = IslandNoticeAutoDismissPolicy.pollNanoseconds
            while !Task.isCancelled {
                let hovering = IslandController.shared?.isHoveringIsland == true
                if IslandNoticeAutoDismissPolicy.shouldDismissNow(
                    expandsDuringSettingsSession: true,
                    settingsBlocksExpand: false,
                    holdWhileHovering: true,
                    isHovering: hovering,
                    elapsedNanoseconds: elapsed,
                    displayNanoseconds: nanos
                ) {
                    break
                }
                try? await Task.sleep(nanoseconds: poll)
                if !hovering {
                    elapsed += poll
                }
            }
            guard !Task.isCancelled else { return }
            guard self.pending?.phase == .completed else { return }
            AppLog.warn("Download", "完成态停留结束，自动撤常驻", [
                "name": self.pending?.fileName ?? "",
                "hoverPaused": IslandController.shared?.isHoveringIsland == true
            ])
            self.clearPending(reason: "completedAutoDismiss")
            // 指针不在岛上时一并收起，避免留下空岛。
            if IslandController.shared?.isHoveringIsland != true {
                IslandController.shared?.collapse(reason: "downloadCompletedAutoDismiss")
            }
        }
    }

    private func cancelCompletedAutoDismiss() {
        completedDismissTask?.cancel()
        completedDismissTask = nil
    }

    private func installOpenShortcutMonitorIfNeeded() {
        guard DownloadCompleteSettings.shared.keyboardShortcutEnabled,
              pending?.phase == .completed
        else {
            uninstallOpenShortcutMonitor()
            return
        }
        let chord = DownloadCompleteSettings.shared.hotKey
        if registeredOpenChord == chord { return }
        uninstallOpenShortcutMonitor()
        GlobalHotKeyCenter.shared.register(id: Self.openHotKeyID, chord: chord) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.pending?.phase == .completed else { return }
                AppLog.warn("Download", "全局快捷键打开下载完成项", [
                    "chord": DownloadCompleteSettings.shared.hotKey.displayString
                ])
                _ = self.handleClick()
            }
        }
        registeredOpenChord = chord
        AppLog.warn("Download", "已注册完成态全局快捷键", [
            "chord": chord.displayString
        ])
    }

    private func uninstallOpenShortcutMonitor() {
        guard registeredOpenChord != nil else { return }
        GlobalHotKeyCenter.shared.unregister(id: Self.openHotKeyID)
        registeredOpenChord = nil
        AppLog.debug("Download", "已注销完成态全局快捷键")
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
                .creationDateKey,
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
            guard let temp = DownloadPathLogic.matchedTempSuffix(name) else { continue }
            let tempPath = url.path
            seenTemp.insert(tempPath)

            let stripped = String(name.dropLast(temp.count))
            let unconfirmed = DownloadPathLogic.isUnconfirmedTempBase(stripped)
            let displayName: String = unconfirmed
                ? L10n.DownloadComplete.downloadingPlaceholderName
                : stripped
            // 仅当成品路径尚不存在时才当作 rename 提示；已存在的同名旧文件不能当 preferred。
            let hintedFinal: String? = {
                guard !unconfirmed else { return nil }
                let candidate = dir.appendingPathComponent(stripped)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return nil
                }
                return candidate.path
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
                track.finalPath = hintedFinal
                track.isUnconfirmed = unconfirmed
                if track.totalBytes == nil {
                    track.totalBytes = resolveTotalBytes(
                        tempURL: url,
                        displayName: displayName,
                        received: bytes
                    )
                } else if bytes > 0, let total = track.totalBytes, bytes > total {
                    // 估长偏短时抬到已收，避免环卡死在 100% 前。
                    track.totalBytes = bytes
                }
                tracks[tempPath] = track
            } else {
                let total = resolveTotalBytes(
                    tempURL: url,
                    displayName: displayName,
                    received: bytes
                )
                tracks[tempPath] = TempTrack(
                    finalPath: hintedFinal,
                    displayName: displayName,
                    lastBytes: bytes,
                    lastSampleAt: now,
                    emaSpeed: 0,
                    sampleCount: 0,
                    isUnconfirmed: unconfirmed,
                    totalBytes: total,
                    startedAt: now
                )
                AppLog.warn("Download", "见下载临时件", [
                    "temp": name,
                    "final": displayName,
                    "unconfirmed": unconfirmed,
                    "total": total ?? -1,
                    "reason": reason
                ])
            }
        }

        // 临时件消失 → 解析成品并启动稳定窗（含 rename 竞态重试）。
        for (tempPath, track) in tracks {
            if seenTemp.contains(tempPath) { continue }
            tracks.removeValue(forKey: tempPath)
            AppLog.warn("Download", "临时件消失，等待成品", [
                "temp": URL(fileURLWithPath: tempPath).lastPathComponent,
                "hint": track.displayName,
                "hasFinalHint": track.finalPath != nil,
                "reason": reason
            ])
            scheduleStabilityCheck(
                preferredPath: track.finalPath,
                displayName: track.isUnconfirmed ? nil : track.displayName,
                fallbackTempPath: tempPath,
                reason: reason,
                notBefore: track.startedAt.addingTimeInterval(-2)
            )
        }

        if let best = bestTemp, let track = tracks[best.path] {
            orphanDownloadingSince = nil
            let speed: Double? = track.sampleCount >= 2 && track.emaSpeed >= DownloadTransferFormatting.minimumDisplaySpeed
                ? track.emaSpeed
                : nil
            let next = DownloadCompleteItem(
                path: best.path,
                fileName: track.displayName,
                phase: .downloading,
                bytesReceived: track.lastBytes >= 0 ? track.lastBytes : nil,
                totalBytes: track.totalBytes,
                speedBytesPerSecond: speed,
                updatedAt: now
            )
            let identityChanged = pending?.path != next.path
                || pending?.phase != .downloading
                || pending?.fileName != next.fileName
            let progressChanged = pending?.bytesReceived != next.bytesReceived
                || pending?.totalBytes != next.totalBytes
                || pending?.speedBytesPerSecond != next.speedBytesPerSecond
            pending = next
            if identityChanged {
                AppLog.warn("Download", "下载进行中上岛", [
                    "name": next.fileName,
                    "bytes": next.bytesReceived ?? -1,
                    "total": next.totalBytes ?? -1,
                    "speed": Int(speed ?? 0),
                    "reason": reason
                ])
                notifyResidentsChanged()
            } else if progressChanged, next.totalBytes != nil {
                AppLog.debug("Download", "下载进度已更新", [
                    "name": next.fileName,
                    "bytes": next.bytesReceived ?? -1,
                    "total": next.totalBytes ?? -1,
                    "fraction": String(format: "%.2f", next.progressFraction ?? -1)
                ])
            }
            return
        }

        // 无临时件：若仍挂着「下载中」，兜底切完成或清理，避免永远停在进行中。
        if let item = pending, item.phase == .downloading, seenTemp.isEmpty {
            if orphanDownloadingSince == nil {
                orphanDownloadingSince = now
            }
            if let since = orphanDownloadingSince,
               now.timeIntervalSince(since) >= orphanGrace,
               stabilityTasks.isEmpty {
                reconcileOrphanDownloading(item, entries: entries, reason: reason)
            }
        } else if pending?.phase != .downloading {
            orphanDownloadingSince = nil
        }
    }

    /// 临时已空、稳定任务也空，但仍停在 downloading → 找最近成品或撤掉。
    private func reconcileOrphanDownloading(
        _ item: DownloadCompleteItem,
        entries: [URL],
        reason: String
    ) {
        if let url = DownloadPathLogic.resolveFinalURL(
            preferredPath: nil,
            displayName: item.fileName == L10n.DownloadComplete.downloadingPlaceholderName
                ? nil
                : item.fileName,
            placeholderName: L10n.DownloadComplete.downloadingPlaceholderName,
            directory: downloadsDirectoryURL,
            entries: entries,
            recentWindow: recentFinalWindow,
            notBefore: orphanDownloadingSince?.addingTimeInterval(-2)
        ) {
            let bytes = Self.byteCount(at: url)
            AppLog.warn("Download", "孤儿进行中已对上成品，切完成态", [
                "from": item.fileName,
                "to": url.lastPathComponent,
                "reason": reason
            ])
            acceptCompleted(
                path: url.path,
                fileName: url.lastPathComponent,
                bytes: bytes,
                reason: "orphan:\(reason)"
            )
            return
        }
        AppLog.warn("Download", "孤儿进行中找不到成品，撤常驻", [
            "name": item.fileName,
            "reason": reason
        ])
        clearPending(reason: "orphanNoFinal:\(reason)")
    }

    private func scheduleStabilityCheck(
        preferredPath: String?,
        displayName: String?,
        fallbackTempPath: String,
        reason: String,
        attempt: Int = 0,
        notBefore: Date? = nil
    ) {
        let taskKey = preferredPath ?? displayName ?? fallbackTempPath
        stabilityTasks[taskKey]?.cancel()
        let sleepNano = attempt == 0 ? stabilityNanoseconds : missingFinalRetryNanoseconds
        stabilityTasks[taskKey] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: sleepNano)
            guard !Task.isCancelled else {
                stabilityTasks[taskKey] = nil
                return
            }

            let entries = (try? FileManager.default.contentsOfDirectory(
                at: downloadsDirectoryURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                    .totalFileAllocatedSizeKey,
                    .isDirectoryKey,
                ],
                options: [.skipsHiddenFiles]
            )) ?? []

            guard let url = DownloadPathLogic.resolveFinalURL(
                preferredPath: preferredPath,
                displayName: displayName,
                placeholderName: L10n.DownloadComplete.downloadingPlaceholderName,
                directory: downloadsDirectoryURL,
                entries: entries,
                recentWindow: recentFinalWindow,
                notBefore: notBefore
            ) else {
                if attempt + 1 < missingFinalMaxAttempts {
                    AppLog.warn("Download", "成品尚未出现，重试", [
                        "hint": displayName ?? preferredPath ?? "",
                        "attempt": attempt + 1,
                        "reason": reason
                    ])
                    stabilityTasks[taskKey] = nil
                    scheduleStabilityCheck(
                        preferredPath: preferredPath,
                        displayName: displayName,
                        fallbackTempPath: fallbackTempPath,
                        reason: reason,
                        attempt: attempt + 1,
                        notBefore: notBefore
                    )
                    return
                }
                stabilityTasks[taskKey] = nil
                AppLog.warn("Download", "重试后仍无成品", [
                    "hint": displayName ?? preferredPath ?? "",
                    "reason": reason
                ])
                return
            }

            let size1 = Self.byteCount(at: url)
            try? await Task.sleep(nanoseconds: stabilityNanoseconds)
            guard !Task.isCancelled else {
                stabilityTasks[taskKey] = nil
                return
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                stabilityTasks[taskKey] = nil
                if attempt + 1 < missingFinalMaxAttempts {
                    scheduleStabilityCheck(
                        preferredPath: preferredPath,
                        displayName: displayName,
                        fallbackTempPath: fallbackTempPath,
                        reason: "restableMissing",
                        attempt: attempt + 1,
                        notBefore: notBefore
                    )
                }
                return
            }
            let size2 = Self.byteCount(at: url)
            guard size1 >= 0, size1 == size2 else {
                AppLog.warn("Download", "成品 size 未稳，再等", [
                    "name": url.lastPathComponent,
                    "s1": size1,
                    "s2": size2
                ])
                stabilityTasks[taskKey] = nil
                scheduleStabilityCheck(
                    preferredPath: url.path,
                    displayName: url.lastPathComponent,
                    fallbackTempPath: fallbackTempPath,
                    reason: "restable",
                    attempt: min(attempt + 1, missingFinalMaxAttempts - 1),
                    notBefore: notBefore
                )
                return
            }
            stabilityTasks[taskKey] = nil
            acceptCompleted(
                path: url.path,
                fileName: url.lastPathComponent,
                bytes: size2,
                reason: reason
            )
        }
    }

    private func acceptCompleted(
        path: String,
        fileName: String,
        bytes: Int64,
        reason: String
    ) {
        let key = path
        let now = Date()
        if let last = recentCompleted[key], now.timeIntervalSince(last) < dedupeWindow {
            AppLog.warn("Download", "同路径去抖，跳过", ["name": fileName])
            // 若岛上仍是进行中，仍要切到完成，避免卡死。
            if pending?.phase == .downloading {
                rememberCompletedSize(fileName: fileName, bytes: bytes)
                pending = DownloadCompleteItem(
                    path: path,
                    fileName: fileName,
                    phase: .completed,
                    bytesReceived: bytes >= 0 ? bytes : nil,
                    totalBytes: bytes >= 0 ? bytes : nil,
                    speedBytesPerSecond: nil,
                    updatedAt: now,
                    completedAt: now,
                    sourceBundleID: Self.quarantineAgentBundleID(for: path)
                )
                orphanDownloadingSince = nil
                AppLog.warn("Download", "去抖但仍从进行中切到完成态", ["name": fileName])
                notifyResidentsChanged()
                beginCompletedPresentation()
            }
            return
        }
        recentCompleted[key] = now
        pruneRecent(now: now)
        orphanDownloadingSince = nil
        rememberCompletedSize(fileName: fileName, bytes: bytes)

        let item = DownloadCompleteItem(
            path: path,
            fileName: fileName,
            phase: .completed,
            bytesReceived: bytes >= 0 ? bytes : nil,
            totalBytes: bytes >= 0 ? bytes : nil,
            speedBytesPerSecond: nil,
            updatedAt: now,
            completedAt: now,
            sourceBundleID: Self.quarantineAgentBundleID(for: path)
        )
        let wasDownloading = pending?.phase == .downloading
        pending = item
        AppLog.warn("Download", "下载完成，已切完成态", [
            "name": item.fileName,
            "bytes": bytes,
            "fromDownloading": wasDownloading,
            "reason": reason,
            "agent": item.sourceBundleID ?? ""
        ])
        notifyResidentsChanged()
        beginCompletedPresentation()
    }

    private func beginCompletedPresentation() {
        refreshOpenShortcutMonitor()
        scheduleCompletedAutoDismiss()
    }

    private func rememberCompletedSize(fileName: String, bytes: Int64) {
        guard bytes > 0 else { return }
        lastCompletedBytesAny = bytes
        let base = DownloadPathLogic.canonicalBaseName(fileName)
        lastCompletedBytesByBase[base] = bytes
    }

    /// 浏览器元数据 → 同系列上次完成 → 最近任意完成；都没有则 nil（环不确定转）。
    private func resolveTotalBytes(
        tempURL: URL,
        displayName: String,
        received: Int64
    ) -> Int64? {
        let browser = DownloadProgressLookup.snapshot(
            tempURL: tempURL,
            displayName: displayName
        )
        if let total = browser.totalBytes, total > 0 {
            AppLog.warn("Download", "总长来自浏览器元数据", [
                "name": displayName,
                "total": total
            ])
            return total
        }

        let base = DownloadPathLogic.canonicalBaseName(displayName)
        if !DownloadPathLogic.isUnconfirmedTempBase(displayName),
           let prior = lastCompletedBytesByBase[base],
           prior > 0 {
            AppLog.warn("Download", "总长沿用同系列上次完成", [
                "name": displayName,
                "base": base,
                "total": prior
            ])
            return max(prior, received)
        }

        if let any = lastCompletedBytesAny, any > 0 {
            AppLog.warn("Download", "总长沿用最近完成估", [
                "name": displayName,
                "total": any
            ])
            return max(any, received)
        }
        return nil
    }

    /// 启动时扫下载目录，用近期成品喂进度环估长（Chrome History 常被 TCC 挡住）。
    private func seedPriorCompletedSizes() {
        let dir = downloadsDirectoryURL
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .isDirectoryKey,
            ],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        var newest: (date: Date, bytes: Int64)?
        for url in entries {
            let name = url.lastPathComponent
            if DownloadPathLogic.matchedTempSuffix(name) != nil { continue }
            if name == ".DS_Store" || name == ".localized" { continue }
            let vals = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
            ])
            let stamp = vals?.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(stamp) <= 7 * 24 * 3600 else { continue }
            let bytes = Self.byteCount(at: url)
            guard bytes > 0 else { continue }
            let base = DownloadPathLogic.canonicalBaseName(name)
            if lastCompletedBytesByBase[base] == nil
                || (vals?.contentModificationDate ?? .distantPast)
                    > (newest?.date ?? .distantPast) {
                lastCompletedBytesByBase[base] = bytes
            }
            if newest == nil || stamp > newest!.date {
                newest = (stamp, bytes)
            }
        }
        if let newest {
            lastCompletedBytesAny = newest.bytes
        }
        if !lastCompletedBytesByBase.isEmpty {
            AppLog.warn("Download", "已从下载目录预热进度估长", [
                "bases": lastCompletedBytesByBase.count,
                "any": lastCompletedBytesAny ?? -1
            ])
        }
    }

    private func pruneRecent(now: Date) {
        recentCompleted = recentCompleted.filter { now.timeIntervalSince($0.value) < dedupeWindow * 2 }
    }

    private func notifyResidentsChanged() {
        NotificationCenter.default.post(name: .downloadCompleteResidentsDidChange, object: nil)
        IslandNoticeCenter.shared.refreshResidentsFromDownload()
        // 露出「打开」：收起番茄等展开页并对齐可点区（否则打开钮不在树上、整段点穿）。
        if showsCompactStandby {
            IslandController.shared?.ensureDownloadCompactClickable(reason: "residentsChanged")
        }
    }

    // MARK: - File size

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
