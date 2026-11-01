import AppKit
import Combine
import Foundation
import MediaRemoteAdapter
import SwiftUI

/// 正在播放：有 Now Playing 会话时上岛（播放或暂停均展示）。
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

    private let context: WidgetContext
    private let service = NowPlayingService.shared

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    /// 卡内自带曲目信息，岛顶栏不再重复。
    var title: String { "" }

    private var observers: Set<AnyCancellable> = []
    private let model = MediaNowPlayingModel()

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
        let shouldShow = snap?.hasTrack == true
        updateDemand(shouldShow: shouldShow, reason: reason)

        if let snap, shouldShow {
            model.apply(snap)
        } else {
            model.applyEmpty()
        }

        if reason != "trackChanged" {
            context.log("媒体展示状态", fields: [
                "reason": reason,
                "onIsland": shouldShow,
                "playing": snap?.isPlaying ?? false,
                "bundle": snap?.bundleIdentifier ?? "nil"
            ])
        }
    }

    private func updateDemand(shouldShow: Bool, reason: String) {
        if shouldShow {
            if !wantsDisplay {
                wantsDisplay = true
                requestedAt = Date()
                AppLog.info("Media", "申请展示（正在播放）", ["reason": reason])
                Task { @MainActor [weak self] in
                    guard let self, self.wantsDisplay else { return }
                    self.context.requestDisplay()
                    AppLog.debug("Media", "已提交 requestDisplay", ["reason": reason])
                }
            }
        } else if wantsDisplay {
            wantsDisplay = false
            context.withdrawDisplay()
            AppLog.info("Media", "撤回展示", ["reason": reason])
        }
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
