import AppKit
import SwiftUI

/// 播放中收起岛左右翼：左封面+歌名，右动态均衡条+已播时长。
struct MediaCompactStandbyView: View {
    let title: String
    let artwork: NSImage?
    let elapsedText: String
    let isPlaying: Bool
    /// 设置样张可关，避免 TimelineView 拖垮设置窗。
    var animatedEqualizer: Bool = true

    private let eqGreen = Color(red: 0.196, green: 0.843, blue: 0.294) // #32D74B

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                artworkThumb
                Text(title.isEmpty ? L10n.Media.widgetName : title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                MediaCompactEqualizerBars(
                    isPlaying: isPlaying,
                    tint: eqGreen,
                    animated: animatedEqualizer
                )
                Text(elapsedText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(elapsedText)")
    }

    /// 设置预览用假数据；仅当前选中的待命 Tab 开动画。
    static func previewSample(animatedEqualizer: Bool = true) -> MediaCompactStandbyView {
        MediaCompactStandbyView(
            title: L10n.Media.previewSampleTitle,
            artwork: MediaIslandCardView.previewArtwork,
            elapsedText: L10n.Media.previewStandbyBadge,
            isPlaying: true,
            animatedEqualizer: animatedEqualizer
        )
    }

    private var artworkThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.12))
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(width: 22, height: 22)
    }

    /// 从快照格式化为 `02:14`（分钟补零）。
    static func formatElapsed(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// 收起态右侧三柱律动：播放跳动，暂停静止。
struct MediaCompactEqualizerBars: View {
    let isPlaying: Bool
    let tint: Color
    var animated: Bool = true

    private let periods: [Double] = [0.55, 0.38, 0.62]
    private let minHeights: [CGFloat] = [5, 9, 5]
    private let maxHeights: [CGFloat] = [10, 14, 10]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying || !animated)) { context in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: height(for: index, at: context.date))
                }
            }
            .frame(width: 12, height: 14, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func height(for index: Int, at date: Date) -> CGFloat {
        if !animated {
            return (minHeights[index] + maxHeights[index]) * 0.5
        }
        guard isPlaying else { return minHeights[index] }
        let t = date.timeIntervalSinceReferenceDate
        let phase = sin(t * (.pi * 2 / periods[index]) + Double(index) * 1.35)
        let normalized = (phase + 1) * 0.5
        return minHeights[index] + (maxHeights[index] - minHeights[index]) * normalized
    }
}
