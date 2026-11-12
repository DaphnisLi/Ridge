import AppKit
import SwiftUI

/// 嵌入「正在播放」小组件预览页的配置区。
struct MediaWidgetConfigSection: View {
    /// 左侧为常驻小岛「正在播放」，右侧才是点按后的展开面板。
    @State private var previewTab: MediaPreviewTab = .playing

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            islandPreviewCard
            supportedPlayersCard
        }
        .onAppear {
            // 预览只用假数据；勿在此 start Now Playing，避免设置窗跟真播放 0.5s 刷。
            AppLog.debug("Media", "媒体配置区已显示（预览页）", ["tab": previewTab.rawValue])
        }
    }

    private var islandPreviewCard: some View {
        SettingsIslandStage(
            options: MediaPreviewTab.allCases.map(stageOption),
            selection: Binding(
                get: { previewTab.rawValue },
                set: { previewTab = MediaPreviewTab(rawValue: $0) ?? .playing }
            )
        ) { option in
            let tab = MediaPreviewTab(rawValue: option.id) ?? .playing
            Group {
                switch tab {
                case .playing:
                    // 待命黑岛与「下一场会议」同宽同高同 chrome。
                    WidgetSamplePreview.meetingMatchedCompactChrome(
                        minHeight: SettingsIslandPreviewWidth.tipDetailMinHeight
                    ) {
                        MediaCompactStandbyView.previewSample(animatedEqualizer: true)
                    }
                case .expanded:
                    MediaIslandCardView.previewSample(animatedEqualizer: false)
                        .padding(.horizontal, IslandChrome.contentHorizontal)
                        .padding(.vertical, IslandChrome.contentBottom)
                }
            }
            .id(tab.rawValue)
        }
    }

    private func stageOption(_ tab: MediaPreviewTab) -> SettingsIslandStageOption {
        SettingsIslandStageOption(
            id: tab.rawValue,
            title: tab.stageTitle,
            badge: tab.stageBadge,
            symbol: tab.symbol,
            tint: tab.tint,
            maxIslandWidth: SettingsIslandPreviewWidth.tip,
            // 待命 hugs（会议同款）；展开拉满 tip 上限后再缩到 290。
            hugsContent: tab.isCompact,
            bottomRadius: tab.isCompact ? 18 : 24,
            outlineStyle: .panel,
            minStageHeight: tab.isCompact
                ? SettingsIslandPreviewWidth.tipStageMinHeight
                : 168,
            compactShell: tab.isCompact
        )
    }

    private var supportedPlayersCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L10n.Media.playersTitle)
                            .font(SettingsChrome.Font.rowTitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Media.playersSubtitle)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                    readyBadge
                }

                HStack(spacing: 8) {
                    ForEach(MediaSupportedPlayer.all) { player in
                        playerSourceCard(player)
                    }
                }
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private var readyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(SettingsChrome.Font.footnote)
            Text(L10n.Media.playersAllSupported)
                .font(SettingsChrome.Font.chip)
        }
        .foregroundStyle(SettingsChrome.onSecondaryContainer)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(SettingsChrome.secondaryContainer)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Media.playersAllSupported)
    }

    private func playerSourceCard(_ player: MediaSupportedPlayer) -> some View {
        HStack(alignment: .center, spacing: 10) {
            playerIcon(player)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.title)
                    .font(SettingsChrome.Font.label)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(player.subtitle)
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsChrome.outlineVariant, lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.title)，\(player.subtitle)")
    }

    @ViewBuilder
    private func playerIcon(_ player: MediaSupportedPlayer) -> some View {
        if let image = player.cachedIcon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(player.fallbackTint)
                Image(systemName: player.fallbackSymbol)
                    .font(SettingsChrome.Font.iconInline)
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - 预览形态

private enum MediaPreviewTab: String, CaseIterable, Identifiable {
    /// 播放中常驻小岛（左）。
    case playing
    /// 点按小岛后才出现的展开控制面板（右，非常驻）。
    case expanded

    var id: String { rawValue }

    var isCompact: Bool { self == .playing }

    var stageTitle: String {
        switch self {
        case .playing: return L10n.Media.previewStagePlaying
        case .expanded: return L10n.Media.previewStageExpanded
        }
    }

    var stageBadge: String {
        switch self {
        case .playing: return L10n.Media.previewStandbyBadge
        case .expanded: return L10n.Media.previewExpandedBadge
        }
    }

    var symbol: String {
        switch self {
        case .playing: return "waveform"
        case .expanded: return "music.note.list"
        }
    }

    var tint: Color {
        switch self {
        case .playing: return Color(red: 0.196, green: 0.843, blue: 0.294)
        case .expanded: return Color(red: 1.0, green: 0.42, blue: 0.29)
        }
    }
}

/// 设置页「支持的播放源」四卡样张（说明性，非实时探测）。
private struct MediaSupportedPlayer: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let bundleIDs: [String]
    let fallbackSymbol: String
    let fallbackTint: Color
    /// 首次解析后缓存，避免每次 body 刷 NSWorkspace。
    let cachedIcon: NSImage?

    static let all: [MediaSupportedPlayer] = [
        make(
            id: "appleMusic",
            title: L10n.Media.playerAppleMusic,
            subtitle: L10n.Media.playerAppleMusicSubtitle,
            bundleIDs: ["com.apple.Music"],
            fallbackSymbol: "music.note",
            fallbackTint: Color(red: 0.98, green: 0.22, blue: 0.35)
        ),
        make(
            id: "spotify",
            title: L10n.Media.playerSpotify,
            subtitle: L10n.Media.playerSpotifySubtitle,
            bundleIDs: ["com.spotify.client"],
            fallbackSymbol: "waveform",
            fallbackTint: Color(red: 0.11, green: 0.73, blue: 0.33)
        ),
        make(
            id: "web",
            title: L10n.Media.playerBrowser,
            subtitle: L10n.Media.playerBrowserSubtitle,
            bundleIDs: ["com.apple.Safari"],
            fallbackSymbol: "safari",
            fallbackTint: Color(red: 0.20, green: 0.48, blue: 0.96)
        ),
        make(
            id: "podcasts",
            title: L10n.Media.playerPodcasts,
            subtitle: L10n.Media.playerPodcastsSubtitle,
            bundleIDs: ["com.apple.podcasts"],
            fallbackSymbol: "headphones",
            fallbackTint: Color(red: 0.55, green: 0.35, blue: 0.95)
        )
    ]

    private static func make(
        id: String,
        title: String,
        subtitle: String,
        bundleIDs: [String],
        fallbackSymbol: String,
        fallbackTint: Color
    ) -> MediaSupportedPlayer {
        MediaSupportedPlayer(
            id: id,
            title: title,
            subtitle: subtitle,
            bundleIDs: bundleIDs,
            fallbackSymbol: fallbackSymbol,
            fallbackTint: fallbackTint,
            cachedIcon: resolveIcon(bundleIDs: bundleIDs)
        )
    }

    private static func resolveIcon(bundleIDs: [String]) -> NSImage? {
        for bid in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 28, height: 28)
            return icon
        }
        return nil
    }
}
