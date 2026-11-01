import SwiftUI

/// 嵌入「正在播放」小组件预览页的配置区。
struct MediaWidgetConfigSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            islandPreviewCard
            introCard
            supportedPlayersCard
        }
        .onAppear {
            NowPlayingService.shared.start()
            AppLog.debug("Media", "媒体配置区已显示（预览页）")
        }
    }

    private var islandPreviewCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                MediaIslandPreviewCapsule()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        SettingsChrome.surfaceContainerLow,
                        SettingsChrome.surfaceContainer.opacity(0.50)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var introCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Media.widgetName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Media.settingsIntro)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var supportedPlayersCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Media.playersTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Media.playersSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(L10n.Media.playersAllSupported)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsChrome.secondary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    playerRow(symbol: "music.note", name: L10n.Media.playerAppleMusic, tint: Color(red: 0.98, green: 0.22, blue: 0.35))
                    playerRow(symbol: "waveform", name: L10n.Media.playerSpotify, tint: Color(red: 0.11, green: 0.73, blue: 0.33))
                    playerRow(symbol: "safari", name: L10n.Media.playerBrowser, tint: Color(red: 0.20, green: 0.48, blue: 0.96))
                    playerRow(symbol: "headphones", name: L10n.Media.playerPodcasts, tint: Color(red: 0.55, green: 0.35, blue: 0.95))
                }
            }
            .padding(16)
        }
    }

    private func playerRow(symbol: String, name: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)

            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsChrome.onSurface)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke.opacity(0.85), lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

private struct MediaIslandPreviewCapsule: View {
    var body: some View {
        MediaIslandCardView.previewSample()
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: 540)
            .frame(minHeight: 148)
            .background(
                MediaIslandPreviewShape(bottomRadius: 26)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        MediaIslandPreviewShape(bottomRadius: 26)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            )
            .clipShape(MediaIslandPreviewShape(bottomRadius: 26))
    }
}

private struct MediaIslandPreviewShape: Shape, InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(bottomRadius, r.height / 2, r.width / 2) - insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(
            center: CGPoint(x: r.maxX - radius, y: r.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(
            center: CGPoint(x: r.minX + radius, y: r.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> MediaIslandPreviewShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
