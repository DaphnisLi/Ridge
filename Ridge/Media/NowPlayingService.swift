import AppKit
import Combine
import Foundation
import MediaRemoteAdapter

/// Now Playing 快照（岛 UI / 设置预览共用）。
struct NowPlayingSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String?
    var isPlaying: Bool
    var duration: TimeInterval
    var elapsed: TimeInterval
    var artwork: NSImage?
    /// 播放源宿主 App 图标（由 bundle id / pid 解析）。
    var appIcon: NSImage?
    var bundleIdentifier: String?
    var applicationName: String?
    var shuffleMode: TrackInfo.ShuffleMode
    var repeatMode: TrackInfo.RepeatMode

    var hasTrack: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

/// 系统 Now Playing：经 MediaRemoteAdapter（perl 桥）读取与控制。
@MainActor
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    @Published private(set) var snapshot: NowPlayingSnapshot?
    @Published private(set) var isListening = false
    @Published private(set) var lastError: String?

    private let controller = MediaController()
    private var progressTimer: Timer?
    private var restartWork: DispatchWorkItem?
    private var clearSnapshotWork: DispatchWorkItem?
    private var started = false
    /// 外推进度用的基准（MediaRemote 通知之间用 playbackRate 插值）。
    private var baseElapsed: TimeInterval = 0
    private var baseTimestamp: Date = .distantPast
    private var playbackRate: Double = 0
    /// bundle id → 宿主图标，避免曲目频繁刷新时重复查 Workspace。
    private var appIconCache: [String: NSImage] = [:]
    /// 网易云等打开 App 时会先推曲目再短暂清空；延迟清空以免 UI 闪成「暂无」。
    private static let clearSnapshotGrace: TimeInterval = 2.5
    /// 首次引导第 1 步：注入假曲目，屏蔽真实 MediaRemote，直到演示结束。
    private(set) var isOnboardingDemoActive = false

    private init() {
        controller.onTrackInfoReceived = { [weak self] info in
            Task { @MainActor in
                self?.apply(info)
            }
        }
        controller.onListenerTerminated = { [weak self] in
            Task { @MainActor in
                self?.handleListenerTerminated()
            }
        }
        controller.onDecodingError = { [weak self] error, _ in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
                AppLog.warn("Media", "Now Playing 解码失败", [
                    "error": error.localizedDescription
                ])
            }
        }
    }

    func start() {
        guard !started else {
            if !isListening {
                beginListening(reason: "restart")
            }
            return
        }
        started = true
        logAdapterBundlePath()
        beginListening(reason: "start")
        startProgressTimer()
        AppLog.info("Media", "Now Playing 服务已启动")
    }

    /// 确认 perl 桥加载的是 App 内嵌框架，而不是 DerivedData 构建目录。
    private func logAdapterBundlePath() {
        let url = Bundle(for: MediaController.self).bundleURL
        let path = url.path
        let insideApp = path.contains(".app/Contents/")
        AppLog.info("Media", "MediaRemoteAdapter 路径", [
            "path": path,
            "insideApp": insideApp
        ])
        if !insideApp {
            AppLog.warn("Media", "Adapter 未从 App 内加载，Now Playing 可能在清理 DerivedData 后失效", [
                "path": path
            ])
        }
    }

    func stop() {
        restartWork?.cancel()
        restartWork = nil
        clearSnapshotWork?.cancel()
        clearSnapshotWork = nil
        stopProgressTimer()
        controller.stopListening()
        isListening = false
        started = false
        snapshot = nil
        AppLog.info("Media", "Now Playing 服务已停止")
    }

    // MARK: - Onboarding demo

    /// 引导演示：岛上出现假「正在播放」小岛；悬停后展开真媒体面板（仍用本快照）。
    func setOnboardingDemoActive(_ active: Bool) {
        guard active != isOnboardingDemoActive else { return }
        isOnboardingDemoActive = active
        clearSnapshotWork?.cancel()
        clearSnapshotWork = nil
        if active {
            let demo = Self.makeOnboardingDemoSnapshot()
            baseElapsed = demo.elapsed
            baseTimestamp = Date()
            playbackRate = 1
            snapshot = demo
            nudgeWidget()
            AppLog.warn("Media", "引导演示假媒体已注入", [
                "title": String(demo.title.prefix(24)),
                "elapsed": Int(demo.elapsed)
            ])
        } else {
            playbackRate = 0
            snapshot = nil
            nudgeWidget()
            AppLog.warn("Media", "引导演示假媒体已撤出")
            // 恢复真实曲目（若有）：主动拉一帧。
            if started {
                controller.getTrackInfo { [weak self] info in
                    Task { @MainActor in
                        guard let self, !self.isOnboardingDemoActive else { return }
                        self.apply(info)
                    }
                }
            }
        }
    }

    private static func makeOnboardingDemoSnapshot() -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: L10n.Media.previewSampleTitle,
            artist: L10n.Media.previewSampleArtist,
            album: nil,
            isPlaying: true,
            duration: 4 * 60 + 3,
            elapsed: 2 * 60 + 14,
            artwork: MediaIslandCardView.previewArtwork,
            appIcon: nil,
            bundleIdentifier: "app.daphnis.Ridge.onboardingDemo",
            applicationName: "Ridge",
            shuffleMode: .off,
            repeatMode: .off
        )
    }

    // MARK: - Controls

    func togglePlayPause() {
        if isOnboardingDemoActive {
            guard var current = snapshot else { return }
            current.isPlaying.toggle()
            playbackRate = current.isPlaying ? 1 : 0
            baseElapsed = current.elapsed
            baseTimestamp = Date()
            snapshot = current
            AppLog.info("Media", "引导演示：切换播放/暂停", ["playing": current.isPlaying])
            return
        }
        AppLog.info("Media", "切换播放/暂停")
        controller.togglePlayPause()
    }

    func nextTrack() {
        guard !isOnboardingDemoActive else {
            AppLog.debug("Media", "引导演示：忽略下一曲")
            return
        }
        AppLog.info("Media", "下一曲")
        controller.nextTrack()
    }

    func previousTrack() {
        guard !isOnboardingDemoActive else {
            AppLog.debug("Media", "引导演示：忽略上一曲")
            return
        }
        AppLog.info("Media", "上一曲")
        controller.previousTrack()
    }

    func toggleShuffle() {
        guard !isOnboardingDemoActive else { return }
        AppLog.info("Media", "切换随机")
        controller.toggleShuffle()
    }

    func toggleRepeat() {
        guard !isOnboardingDemoActive else { return }
        AppLog.info("Media", "切换循环")
        controller.toggleRepeat()
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, seconds)
        AppLog.info("Media", "拖动进度", ["seconds": Int(clamped)])
        baseElapsed = clamped
        baseTimestamp = Date()
        if var current = snapshot {
            current.elapsed = clamped
            snapshot = current
        }
        guard !isOnboardingDemoActive else { return }
        controller.setTime(seconds: clamped)
    }

    // MARK: - Internals

    private func beginListening(reason: String) {
        controller.startListening()
        isListening = true
        AppLog.debug("Media", "开始监听 Now Playing", ["reason": reason])
        // 首帧：主动拉一次，避免只等通知。
        controller.getTrackInfo { [weak self] info in
            Task { @MainActor in
                self?.apply(info)
            }
        }
    }

    private func handleListenerTerminated() {
        isListening = false
        AppLog.warn("Media", "Now Playing 监听进程已退出，将重试")
        scheduleRestart()
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.started else { return }
            self.beginListening(reason: "retry")
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func apply(_ info: TrackInfo?) {
        // 引导演示期间屏蔽真实 Now Playing，避免冲掉假曲目。
        guard !isOnboardingDemoActive else { return }

        guard let payload = info?.payload else {
            scheduleClearSnapshot(reason: "nilPayload")
            return
        }

        let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            scheduleClearSnapshot(reason: "emptyTitle")
            return
        }

        // 有效曲目：取消待清空，立刻刷新。
        clearSnapshotWork?.cancel()
        clearSnapshotWork = nil

        let duration = (payload.durationMicros ?? 0) / 1_000_000
        let elapsed = payload.currentElapsedTime
            ?? ((payload.elapsedTimeMicros ?? 0) / 1_000_000)
        let playing = payload.isPlaying == true
        playbackRate = payload.playbackRate ?? (playing ? 1 : 0)
        baseElapsed = elapsed
        baseTimestamp = Date()

        let bundleID = payload.bundleIdentifier
        let appIcon = resolveAppIcon(bundleID: bundleID, pid: payload.PID)
        // 浏览器等有时把 App 图标塞进 artwork；与宿主图标相同则不当封面。
        let artwork = sanitizedArtwork(payload.artwork, appIcon: appIcon)
        let next = NowPlayingSnapshot(
            title: title,
            artist: (payload.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            album: payload.album,
            isPlaying: playing,
            duration: max(duration, 0),
            elapsed: max(elapsed, 0),
            artwork: artwork,
            appIcon: appIcon,
            bundleIdentifier: bundleID,
            applicationName: payload.applicationName,
            shuffleMode: payload.shuffleMode ?? .off,
            repeatMode: payload.repeatMode ?? .off
        )

        let changedTrack = snapshot?.title != next.title
            || snapshot?.artist != next.artist
            || snapshot?.bundleIdentifier != next.bundleIdentifier
        let changedPlay = snapshot?.isPlaying != next.isPlaying
        snapshot = next

        if changedTrack || changedPlay {
            // warn 落盘，便于排查「在播但不显示」。
            AppLog.warn("Media", "Now Playing 更新", [
                "title": String(title.prefix(24)),
                "playing": playing,
                "bundle": bundleID ?? "?",
                "appIcon": appIcon != nil,
                "duration": Int(duration)
            ])
        }
        nudgeWidget()
    }

    /// 延迟清空：打开播放器未点播放时，系统常会先推曲目再推空帧。
    private func scheduleClearSnapshot(reason: String) {
        guard !isOnboardingDemoActive else { return }
        guard snapshot != nil else { return }
        if clearSnapshotWork != nil {
            AppLog.debug("Media", "Now Playing 清空已在等待", ["reason": reason])
            return
        }
        AppLog.warn("Media", "Now Playing 收到空帧，延迟清空", [
            "reason": reason,
            "keepTitle": String((snapshot?.title ?? "").prefix(24)),
            "grace": Self.clearSnapshotGrace
        ])
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clearSnapshotWork = nil
            guard self.snapshot != nil else { return }
            AppLog.warn("Media", "Now Playing 已清空（宽限期结束）", ["reason": reason])
            self.snapshot = nil
            self.playbackRate = 0
            self.nudgeWidget()
        }
        clearSnapshotWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clearSnapshotGrace, execute: work)
    }

    private func sanitizedArtwork(_ artwork: NSImage?, appIcon: NSImage?) -> NSImage? {
        guard let artwork else { return nil }
        guard let appIcon,
              let artData = artwork.tiffRepresentation,
              let iconData = appIcon.tiffRepresentation
        else { return artwork }
        if artData == iconData {
            AppLog.debug("Media", "封面与 App 图标相同，已忽略封面")
            return nil
        }
        return artwork
    }

    /// 优先用 pid + SoundHostAppResolver（能剥 Helper）；否则按 bundle id 查宿主 .app 图标。
    private func resolveAppIcon(bundleID: String?, pid: pid_t?) -> NSImage? {
        if let pid, pid > 0 {
            let identity = SoundHostAppResolver.resolve(pid: pid, processBundleID: bundleID)
            if let icon = identity.icon {
                if let key = identity.bundleID ?? bundleID {
                    appIconCache[key] = icon
                }
                return icon
            }
        }

        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = appIconCache[bundleID] {
            return cached
        }

        var candidates = [bundleID]
        for parent in SoundHostAppResolver.parentBundleIDCandidates(bundleID) where !candidates.contains(parent) {
            candidates.append(parent)
        }
        for bid in candidates {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            guard icon.size.width >= 1, icon.size.height >= 1 else { continue }
            appIconCache[bundleID] = icon
            AppLog.debug("Media", "已解析播放源图标", [
                "request": bundleID,
                "resolved": bid
            ])
            return icon
        }

        AppLog.debug("Media", "播放源图标未找到", ["bundle": bundleID])
        return nil
    }

    private func nudgeWidget() {
        WidgetRuntime.shared.nudgeContentWidget(
            "builtin.media",
            hasContent: snapshot?.hasTrack == true
        )
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func tickProgress() {
        guard var current = snapshot, current.isPlaying, playbackRate > 0 else { return }
        let elapsed = baseElapsed + Date().timeIntervalSince(baseTimestamp) * playbackRate
        let capped: TimeInterval
        if current.duration > 0 {
            capped = min(max(elapsed, 0), current.duration)
        } else {
            capped = max(elapsed, 0)
        }
        guard abs(capped - current.elapsed) >= 0.2 else { return }
        current.elapsed = capped
        snapshot = current
    }
}
