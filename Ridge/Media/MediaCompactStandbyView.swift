import AppKit
import SwiftUI

/// 播放中常驻小岛：左翼封面+歌名，右翼律动+时长；双槽一侧 flush（音符+时长+律动）。
struct MediaCompactStandbyView: View {
    let title: String
    let artwork: NSImage?
    let elapsedText: String
    let isPlaying: Bool
    /// 设置样张可关，避免 TimelineView 拖垮设置窗。
    var animatedEqualizer: Bool = true
    /// 双槽一侧：左翼内容（音符+时长+律动）。
    var flushSide: IslandFlushWingStyle.Side? = nil
    /// 真岛双槽：只画内容，不套黑胶囊（岛壳已黑；再套会叠成下方一条）。
    var bareWingContent: Bool = false
    /// 设置预览无真刘海时的占位宽。
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth

    /// 满岛待命原色 #32D74B；半块 flush 另用 `flushEqGreen`。
    private let eqGreen = Color(red: 0.196, green: 0.843, blue: 0.294)
    private let flushEqGreen = IslandFlushWingStyle.accentSuccess
    private let artworkSide: CGFloat = 22
    private let leftClusterSpacing: CGFloat = 8
    /// 满岛右翼：律动条与时长数字间距（原 6 过挤）。
    private let equalizerElapsedSpacing: CGFloat = 12

    private var notchWidth: CGFloat {
        envNotchWidth > 40 ? envNotchWidth : previewNotchWidth
    }

    var body: some View {
        if flushSide != nil {
            wingLeadContent(bare: bareWingContent)
        } else {
            fullStandbyBody
        }
    }

    private func wingLeadContent(bare: Bool) -> some View {
        // 仅双槽半块：音符 | 时长 | 律动。满岛待命仍用 `fullStandbyBody` + `eqGreen`。
        let spacer = bare
            ? IslandFlushWingStyle.bareContentSpacerMin
            : CGFloat(4)
        let row = HStack(spacing: 0) {
            HStack(spacing: IslandFlushWingStyle.iconLabelSpacing) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(flushEqGreen)
                Text(elapsedText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: spacer)
            MediaCompactEqualizerBars(
                isPlaying: isPlaying,
                tint: flushEqGreen,
                animated: animatedEqualizer
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(elapsedText)")

        if bare {
            return AnyView(row.islandBareFlushWingContent())
        }
        return AnyView(
            IslandFlushWingCapsule(side: flushSide ?? .leading) { row }
        )
    }

    private var fullStandbyBody: some View {
        GeometryReader { geo in
            let total = max(geo.size.width, 1)
            // 中段留给刘海，左右翼等宽；歌名只在左翼可见区内轮播。
            let notch = min(max(notchWidth, 1), total * 0.72)
            let wing = max(0, (total - notch) / 2)
            let titleBudget = max(0, wing - artworkSide - leftClusterSpacing)

            HStack(spacing: 0) {
                HStack(spacing: leftClusterSpacing) {
                    artworkThumb
                    IslandCompactTitleMarquee(
                        text: title.isEmpty ? L10n.Media.widgetName : title,
                        animated: animatedEqualizer,
                        visibleWidth: titleBudget,
                        fontSize: 12,
                        fontWeight: .semibold,
                        logTag: "Media"
                    )
                }
                .frame(width: wing, alignment: .leading)
                .clipped()

                Color.clear
                    .frame(width: notch)
                    .accessibilityHidden(true)

                HStack(spacing: equalizerElapsedSpacing) {
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
                // 律动+时长作为一组在右翼水平居中（勿再贴右缘）。
                .frame(width: wing, alignment: .center)
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
