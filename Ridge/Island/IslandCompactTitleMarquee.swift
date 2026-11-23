import SwiftUI

/// 收起/翼 tip 左侧标题横向轮播：`visibleWidth` 放不下时滚动，与音乐歌名同口径。
struct IslandCompactTitleMarquee: View {
    let text: String
    var animated: Bool = true
    /// 真正露出来的宽度（图标已扣除）。
    var visibleWidth: CGFloat
    var fontSize: CGFloat = 12
    var fontWeight: Font.Weight = .semibold
    var foreground: Color = .white
    /// 滚动速度（pt/s）。
    var speed: CGFloat = 28
    /// 两段文案间距。
    var gap: CGFloat = 28
    /// 滚到头尾后的停顿。
    var holdSeconds: TimeInterval = 1.4
    var logTag: String = "Island"

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
        .frame(width: boxWidth, height: max(14, fontSize + 4), alignment: .leading)
        .clipped()
        .background(alignment: .leading) {
            titleLabel
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: IslandCompactTitleWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                )
        }
        .onPreferenceChange(IslandCompactTitleWidthKey.self) { width in
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
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(foreground)
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
        AppLog.debug(logTag, "标题启动轮播", [
            "textW": Int(textWidth),
            "visibleW": Int(boxWidth),
            "len": text.count
        ])
    }
}

private struct IslandCompactTitleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
