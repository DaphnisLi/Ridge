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
    /// 本段曲目会话是否已自动展开过（防重建/闪断后反复 expand 导致收不起来）。
    private var didAutoExpandForSession = false

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
        IslandNoticeCenter.shared.$current
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                // 其它瞬时条结束后，若仍有曲目且未点进，补投实况邀请。
                guard payload == nil else { return }
                self?.reevaluate(reason: "noticeCleared")
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
        } else if !wantsDisplay {
            // 仍在争夺时保留上一帧曲目，勿闪成「暂无正在播放的内容」。
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
            withdrawDebounceTask?.cancel()
            withdrawDebounceTask = nil

            let opened = LiveIslandGate.shared.isOpened(Self.manifest.id)
            if opened {
                dismissLiveInvite()
                let becameVisible = !wantsDisplay
                let alreadyDemanding = WidgetRuntime.shared.isDemanding(Self.manifest.id)
                if becameVisible {
                    wantsDisplay = true
                    requestedAt = Date()
                    AppLog.info("Media", "实况已点进，申请展示", [
                        "reason": reason,
                        "alreadyDemanding": alreadyDemanding
                    ])
                }
                guard becameVisible else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.wantsDisplay else { return }
                    WidgetRuntime.shared.revealPage(
                        Self.manifest.id,
                        reason: "media:\(reason)",
                        remember: false
                    )
                    let shouldExpand = !self.didAutoExpandForSession && !alreadyDemanding
                    if shouldExpand {
                        self.didAutoExpandForSession = true
                        IslandController.shared?.expand(reason: "mediaNowPlaying")
                        self.scheduleAutoCollapseIfNeeded()
                    }
                    AppLog.warn("Media", "媒体页已就绪", [
                        "reason": reason,
                        "expand": shouldExpand,
                        "title": String((self.service.snapshot?.title ?? "").prefix(24)),
                        "active": WidgetRuntime.shared.activeID ?? "nil"
                    ])
                }
            } else {
                // 未点进：撤内容页，改投实况邀请提示。
                if wantsDisplay {
                    wantsDisplay = false
                    context.withdrawDisplay()
                }
                presentLiveInvite(reason: reason)
            }
            return
        }

        scheduleDebouncedWithdraw(reason: reason)
    }

    private func presentLiveInvite(reason: String) {
        let snap = service.snapshot
        let title = snap?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = snap?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let invite = LiveIslandInvite(
            widgetID: Self.manifest.id,
            title: title.isEmpty ? L10n.Media.widgetName : title,
            subtitle: artist.isEmpty ? L10n.Media.liveInviteSubtitle : artist,
            symbol: "music.note"
        )
        let current = IslandNoticeCenter.shared.current
        if case .liveInvite(let existing) = current, existing == invite {
            return
        }
        // 若正展示其它通知，不抢（等其结束后再投）；曲目仍在时下次 reevaluate 会补。
        if let current, current.id != invite.noticeID {
            AppLog.debug("Media", "实况邀请暂缓：其它通知占用", [
                "reason": reason,
                "current": current.id
            ])
            return
        }
        IslandNoticeCenter.shared.present(.liveInvite(invite))
        AppLog.info("Media", "已投递实况邀请提示", [
            "reason": reason,
            "title": String(invite.title.prefix(24))
        ])
    }

    private func dismissLiveInvite() {
        IslandNoticeCenter.shared.dismiss(id: LiveIslandGate.inviteNoticeID(for: Self.manifest.id))
    }

    /// 自动展开后若指针不在岛上，稍后收起，避免点播放后一直挂着。
    private func scheduleAutoCollapseIfNeeded() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard IslandController.shared?.isHoveringIsland != true else { return }
            IslandController.shared?.collapse(reason: "mediaAutoCollapse")
            AppLog.warn("Media", "媒体自动展开后已收起", [
                "hovering": IslandController.shared?.isHoveringIsland ?? false
            ])
        }
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
            self.didAutoExpandForSession = false
            self.model.applyEmpty()
            self.dismissLiveInvite()
            LiveIslandGate.shared.close(Self.manifest.id, reason: "mediaWithdraw:\(reason)")
            self.context.withdrawDisplay()
            if IslandController.shared?.isHoveringIsland != true {
                IslandController.shared?.collapse(reason: "mediaWithdraw")
            }
            AppLog.warn("Media", "已撤回媒体展示（防抖后仍无曲目）", ["reason": reason])
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
