import AppKit
import SwiftUI

/// 媒体岛卡：设置预览与岛上真机共用。
struct MediaIslandCardView: View {
    let title: String
    let artist: String
    let artwork: NSImage?
    let appIcon: NSImage?
    let isPlaying: Bool
    let progress: Double
    let elapsedText: String
    let durationText: String
    var onTogglePlay: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    /// 设置预览关动画，避免库卡/详情 TimelineView 30fps 拖垮设置窗。
    var animatedEqualizer: Bool = true

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var shownProgress: Double {
        isDragging ? dragProgress : min(max(progress, 0), 1)
    }

    private let coral = Color(red: 1.0, green: 0.42, blue: 0.29) // #ff6b4a
    private let coralRose = Color(red: 1.0, green: 0.45, blue: 0.26) // #ff7243
    private let appleMusicRed = Color(red: 0.99, green: 0.24, blue: 0.27) // #fc3c44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                artworkView

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(artist.isEmpty ? " " : artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MediaAudioEqualizerView(isPlaying: isPlaying, tint: coral, animated: animatedEqualizer)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 2) {
                progressBar

                HStack(spacing: 26) {
                    transportButton("backward.fill", size: 14, action: onPrevious)
                        .accessibilityLabel(L10n.Media.previousA11y)
                    playButton
                    transportButton("forward.fill", size: 14, action: onNext)
                        .accessibilityLabel(L10n.Media.nextA11y)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 320)
    }

    private var artworkView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .frame(width: 52, height: 52)
            .shadow(color: .black.opacity(0.40), radius: 6, y: 2)

            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .padding(1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                    )
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let thumbX = width * shownProgress
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white, coralRose, appleMusicRed],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(thumbX, shownProgress > 0 ? 5 : 0), height: 5)
                        .shadow(color: appleMusicRed.opacity(0.40), radius: 3, y: 0)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: appleMusicRed.opacity(0.65), radius: 4)
                        .shadow(color: Color.white.opacity(0.50), radius: 1.5)
                        .overlay(
                            Circle()
                                .fill(appleMusicRed)
                                .frame(width: 3, height: 3)
                        )
                        .offset(x: thumbX - 5)
                        .opacity(shownProgress > 0.01 || isDragging ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragProgress = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            let p = min(max(value.location.x / width, 0), 1)
                            dragProgress = p
                            isDragging = false
                            onSeek?(p)
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(elapsedText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer(minLength: 0)
                Text(durationText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    private var playButton: some View {
        Button(action: { onTogglePlay?() }) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white))
                .shadow(color: Color.white.opacity(0.20), radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? L10n.Media.pauseA11y : L10n.Media.playA11y)
    }

    private func transportButton(
        _ systemName: String,
        size: CGFloat,
        action: (() -> Void)?
    ) -> some View {
        Button(action: { action?() }) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }

    /// 设置页 / 库卡样张（律动条默认静止，防设置窗卡顿）。
    static func previewSample(animatedEqualizer: Bool = false) -> MediaIslandCardView {
        MediaIslandCardView(
            title: L10n.Media.previewSampleTitle,
            artist: L10n.Media.previewSampleArtist,
            artwork: previewArtwork,
            appIcon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
                .map { NSWorkspace.shared.icon(forFile: $0.path) },
            isPlaying: true,
            progress: 0.68,
            elapsedText: "2:59",
            durationText: "-1:28",
            animatedEqualizer: animatedEqualizer
        )
    }

    /// 播放小岛 / 展开面板样张共用假封面（只生成一次）。
    static let previewArtwork: NSImage = makePreviewArtwork()

    /// 假封面：珊瑚渐变 + 音符，避免样张左侧空白。
    private static func makePreviewArtwork() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        NSGradient(colors: [
            NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.29, alpha: 1),
            NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.38, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.06, blue: 0.28, alpha: 1)
        ])?.draw(in: rect, angle: -48)

        if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 46, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white.withAlphaComponent(0.92)]))
            ) {
            let noteSize = NSSize(width: 52, height: 52)
            let noteRect = NSRect(
                x: (size.width - noteSize.width) / 2,
                y: (size.height - noteSize.height) / 2 - 2,
                width: noteSize.width,
                height: noteSize.height
            )
            symbol.draw(in: noteRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        return image
    }
}

// MARK: - Audio equalizer

/// 右侧音乐律动条：播放时持续跳动，暂停时静止；设置样张可关 `animated`。
private struct MediaAudioEqualizerView: View {
    let isPlaying: Bool
    let tint: Color
    var animated: Bool = true

    private let barCount = 5
    /// 各柱相位周期（秒），错开形成律动感。
    private let periods: [Double] = [0.70, 0.45, 0.90, 0.55, 0.80]
    private let minHeights: [CGFloat] = [7, 12, 5, 16, 9]
    private let maxHeights: [CGFloat] = [13, 20, 11, 22, 16]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying || !animated)) { context in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: height(for: index, at: context.date))
                }
            }
            .frame(width: 27, height: 22, alignment: .bottom)
        }
    }

    private func height(for index: Int, at date: Date) -> CGFloat {
        if !animated {
            return (minHeights[index] + maxHeights[index]) * 0.5
        }
        guard isPlaying else { return minHeights[index] }
        let t = date.timeIntervalSinceReferenceDate
        let phase = sin(t * (.pi * 2 / periods[index]) + Double(index) * 1.1)
        let normalized = (phase + 1) * 0.5
        return minHeights[index] + (maxHeights[index] - minHeights[index]) * normalized
    }
}
