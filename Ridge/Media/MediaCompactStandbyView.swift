import AppKit
import SwiftUI

/// 播放中常驻小岛：左翼封面+歌名，右翼律动+时长；中空避开刘海（歌名轮播宽=左翼可见宽）。
struct MediaCompactStandbyView: View {
    let title: String
    let artwork: NSImage?
    let elapsedText: String
    let isPlaying: Bool
    /// 设置样张可关，避免 TimelineView 拖垮设置窗。
    var animatedEqualizer: Bool = true
    /// 设置预览无真刘海时的占位宽。
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth

    private let eqGreen = Color(red: 0.196, green: 0.843, blue: 0.294) // #32D74B
    private let artworkSide: CGFloat = 22
    private let leftClusterSpacing: CGFloat = 8

    private var notchWidth: CGFloat {
        envNotchWidth > 40 ? envNotchWidth : previewNotchWidth
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(geo.size.width, 1)
            // 中段留给刘海，左右翼等宽；歌名只在左翼可见区内轮播。
            let notch = min(max(notchWidth, 1), total * 0.72)
            let wing = max(0, (total - notch) / 2)
            let titleBudget = max(0, wing - artworkSide - leftClusterSpacing)

            HStack(spacing: 0) {
                HStack(spacing: leftClusterSpacing) {
                    artworkThumb
                    MediaCompactTitleMarquee(
                        text: title.isEmpty ? L10n.Media.widgetName : title,
                        animated: animatedEqualizer,
                        visibleWidth: titleBudget
                    )
                }
                .frame(width: wing, alignment: .leading)
                .clipped()

                Color.clear
                    .frame(width: notch)
                    .accessibilityHidden(true)

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
                .frame(width: wing, alignment: .trailing)
                .clipped()
            }
            .frame(width: total, height: geo.size.height)
            .onAppear {
                AppLog.debug("Media", "收起态翼布局", [
                    "total": Int(total),
                    "notch": Int(notch),
                    "wing": Int(wing),
                    "titleBudget": Int(titleBudget)
                ])
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(elapsedText)")
    }

    /// 设置预览用假数据；仅当前选中的「正在播放」Tab 开动画。
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

/// 收起态歌名横向轮播：`visibleWidth` 仅为刘海左侧可见翼宽（不含被挡段）。
private struct MediaCompactTitleMarquee: View {
    let text: String
    var animated: Bool = true
    /// 左翼内真正露出来的宽度（封面已扣除）。
    var visibleWidth: CGFloat
    /// 滚动速度（pt/s）。
    var speed: CGFloat = 28
    /// 两段文案间距。
    var gap: CGFloat = 28
    /// 滚到头尾后的停顿。
    var holdSeconds: TimeInterval = 1.4

    @State private var textWidth: CGFloat = 0
    @State private var didLogMarquee = false

    private var boxWidth: CGFloat { max(0, visibleWidth) }

    private var needsMarquee: Bool {
        animated && textWidth > 0 && boxWidth > 0 && textWidth > boxWidth + 1
    }

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: !needsMarquee)
        ) { context in
            let offset = marqueeOffset(at: context.date)
            HStack(spacing: gap) {
                titleLabel
                if needsMarquee {
                    titleLabel
                }
            }
            .offset(x: offset)
        }
        .frame(width: boxWidth, height: 16, alignment: .leading)
        .clipped()
        .background(alignment: .leading) {
            titleLabel
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MediaCompactTitleWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                )
        }
        .onPreferenceChange(MediaCompactTitleWidthKey.self) { width in
            textWidth = width
            logMarqueeIfNeeded()
        }
        .onChange(of: text) { _, _ in
            didLogMarquee = false
            logMarqueeIfNeeded()
        }
        .onChange(of: visibleWidth) { _, _ in
            didLogMarquee = false
            logMarqueeIfNeeded()
        }
    }

    private var titleLabel: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func marqueeOffset(at date: Date) -> CGFloat {
        guard needsMarquee else { return 0 }
        let cycle = textWidth + gap
        guard cycle > 1, speed > 0 else { return 0 }
        let scrollDuration = TimeInterval(cycle / speed)
        let total = holdSeconds + scrollDuration
        guard total > 0 else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        if phase < holdSeconds { return 0 }
        let progress = (phase - holdSeconds) / scrollDuration
        return -CGFloat(progress) * cycle
    }

    private func logMarqueeIfNeeded() {
        guard needsMarquee, !didLogMarquee else { return }
        didLogMarquee = true
        AppLog.debug("Media", "收起态歌名启动轮播", [
            "textW": Int(textWidth),
            "visibleW": Int(boxWidth),
            "len": text.count
        ])
    }
}

private struct MediaCompactTitleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
