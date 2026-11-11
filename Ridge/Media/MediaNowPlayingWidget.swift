import AppKit
import Combine
import Foundation
import MediaRemoteAdapter
import SwiftUI

/// 正在播放：播放中以小岛常驻；大面板仅在点按小岛后准入，收起即撤出分页。
@MainActor
final class MediaNowPlayingWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.media",
        displayName: L10n.Media.widgetName,
        summary: L10n.Media.widgetSummary,
        source: .builtin,
        kind: .content,
        defaultGridSize: .twoByOne
    )

    /// 服务层已有清空宽限；此处再留余量，避免空帧穿透后立刻拆页。
    private static let withdrawDebounceNanoseconds: UInt64 = 2_800_000_000

    private let context: WidgetContext
    private let service = NowPlayingService.shared

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    /// 卡内自带曲目信息，岛顶栏不再重复。
    var title: String { "" }

    private var observers: Set<AnyCancellable> = []
    private let model = MediaNowPlayingModel()
    private var withdrawDebounceTask: Task<Void, Never>?

    init(context: WidgetContext) {
        self.context = context
        service.start()
        service.$snapshot
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reevaluate(reason: "trackChanged")
            }
            .store(in: &observers)
        reevaluate(reason: "init")
    }

    func makeView() -> AnyView {
        AnyView(
            MediaNowPlayingLiveView(
                model: model,
                onTogglePlay: { [weak self] in self?.service.togglePlayPause() },
                onPrevious: { [weak self] in self?.service.previousTrack() },
                onNext: { [weak self] in self?.service.nextTrack() },
                onSeekFraction: { [weak self] fraction in self?.seek(fraction: fraction) }
            )
        )
    }

    func onAppear() {
        context.log("媒体 onAppear")
        service.start()
        reevaluate(reason: "appear")
    }

    func onDisappear() {
        context.log("媒体 onDisappear")
    }

    func refresh() {
        reevaluate(reason: "refresh")
    }

    private func seek(fraction: Double) {
        guard let snap = service.snapshot, snap.duration > 0 else { return }
        service.seek(to: snap.duration * min(max(fraction, 0), 1))
    }

    private func reevaluate(reason: String) {
        let snap = service.snapshot
        let hasTrack = snap?.hasTrack == true
        updateDemand(hasTrack: hasTrack, reason: reason)

        if let snap, hasTrack {
            model.apply(snap)
        } else if !wantsDisplay {
            // 仍在争夺时保留上一帧曲目，勿闪成「暂无正在播放的内容」。
            model.applyEmpty()
        }

        if reason != "trackChanged" {
            context.log("媒体展示状态", fields: [
                "reason": reason,
                "hasTrack": hasTrack,
                "panelOpen": LiveIslandGate.shared.isOpened(Self.manifest.id),
                "playing": snap?.isPlaying ?? false,
                "bundle": snap?.bundleIdentifier ?? "nil"
            ])
        }
    }

    private func updateDemand(hasTrack: Bool, reason: String) {
        if hasTrack {
            withdrawDebounceTask?.cancel()
            withdrawDebounceTask = nil
            // 有曲目只驱动小岛；大面板须点按 `LiveIslandGate.open`，禁止自动 admit / expand。
            let panelOpen = LiveIslandGate.shared.isOpened(Self.manifest.id)
            wantsDisplay = panelOpen
            if panelOpen, requestedAt == .distantPast {
                requestedAt = Date()
            }
            if reason == "init" || reason == "appear" || reason == "refresh" {
                AppLog.info("Media", "有曲目：仅小岛常驻，大面板待点按", [
                    "reason": reason,
                    "panelOpen": panelOpen,
                    "playing": service.snapshot?.isPlaying ?? false
                ])
            }
            return
        }

        scheduleDebouncedWithdraw(reason: reason)
    }

    private func scheduleDebouncedWithdraw(reason: String) {
        withdrawDebounceTask?.cancel()
        withdrawDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.withdrawDebounceNanoseconds)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            guard self.service.snapshot?.hasTrack != true else {
                AppLog.debug("Media", "撤回已取消：曲目已恢复", ["reason": reason])
                return
            }
            self.wantsDisplay = false
            self.requestedAt = .distantPast
            self.model.applyEmpty()
            LiveIslandGate.shared.close(Self.manifest.id, reason: "mediaWithdraw:\(reason)")
            if IslandController.shared?.isHoveringIsland != true {
                IslandController.shared?.collapse(reason: "mediaWithdraw")
            }
            AppLog.warn("Media", "已撤回媒体展示（防抖后仍无曲目）", ["reason": reason])
        }
    }
}

// MARK: - 播放小岛（收起态）

enum MediaCompactPresence {
    /// 播放中且未被番茄翼占用时，收起岛可展示媒体小岛。
    @MainActor
    static var isActive: Bool {
        !FocusTimerSession.shared.showsCompactStandby
            && WidgetSettings.shared.isEnabled(MediaNowPlayingWidget.manifest.id)
            && NowPlayingService.shared.snapshot?.hasTrack == true
            && NowPlayingService.shared.snapshot?.isPlaying == true
    }

    /// 画面上正是播放小岛：收起态、无瞬时 tip（会议等）盖住。仅此时悬停才开大面板。
    @MainActor
    static var isVisiblyShowingCompact: Bool {
        isActive && IslandNoticeCenter.shared.current == nil
    }

    /// 准入大面板并展开（悬停小岛 / 辅助点按）。
    @MainActor
    static func openExpandedPanel(reason: String) {
        guard isVisiblyShowingCompact else {
            AppLog.debug("Media", "展开大面板跳过：当前不是播放小岛", [
                "reason": reason,
                "active": isActive,
                "notice": IslandNoticeCenter.shared.current?.id ?? ""
            ])
            return
        }
        guard !LiveIslandGate.shared.isOpened(LiveIslandGate.mediaID) else {
            IslandController.shared?.expand(reason: "mediaAlreadyOpen:\(reason)")
            return
        }
        AppLog.info("Media", "播放小岛触发，展开控制面板", [
            "reason": reason,
            "title": String((NowPlayingService.shared.snapshot?.title ?? "").prefix(24))
        ])
        LiveIslandGate.shared.open(LiveIslandGate.mediaID, reason: reason)
    }
}

// MARK: - View model

@MainActor
final class MediaNowPlayingModel: ObservableObject {
    @Published var title: String = L10n.Media.widgetName
    @Published var artist: String = L10n.Media.idleArtist
    @Published var artwork: NSImage?
    @Published var appIcon: NSImage?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var elapsedText = "0:00"
    @Published var durationText = "0:00"

    func applyEmpty() {
        title = L10n.Media.widgetName
        artist = L10n.Media.idleArtist
        artwork = nil
        appIcon = nil
        isPlaying = false
        progress = 0
        elapsedText = "0:00"
        durationText = "0:00"
    }

    func apply(_ snap: NowPlayingSnapshot) {
        title = snap.title
        artist = snap.artist.isEmpty ? (snap.applicationName ?? L10n.Media.unknownArtist) : snap.artist
        artwork = snap.artwork
        appIcon = snap.appIcon
        isPlaying = snap.isPlaying
        progress = snap.progress
        elapsedText = Self.formatTime(snap.elapsed)
        // 右侧显示剩余时长（与经典展开 mockup 一致：-m:ss）
        let remaining = max(0, snap.duration - snap.elapsed)
        durationText = remaining > 0 ? "-\(Self.formatTime(remaining))" : "0:00"
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct MediaNowPlayingLiveView: View {
    @ObservedObject var model: MediaNowPlayingModel
    let onTogglePlay: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeekFraction: (Double) -> Void

    var body: some View {
        MediaIslandCardView(
            title: model.title,
            artist: model.artist,
            artwork: model.artwork,
            appIcon: model.appIcon,
            isPlaying: model.isPlaying,
            progress: model.progress,
            elapsedText: model.elapsedText,
            durationText: model.durationText,
            onTogglePlay: onTogglePlay,
            onPrevious: onPrevious,
            onNext: onNext,
            onSeek: onSeekFraction
        )
    }
}
