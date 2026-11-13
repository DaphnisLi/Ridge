import AppKit
import SwiftUI

/// 媒体展开面板下限：展开瞬间先写入，避免可点区仍停在小岛高度导致底栏按钮点空。
enum MediaExpandedContentSize {
    static let contentWidth: CGFloat = 320
    /// 翼行 + 歌名作者 + 进度 + 控件的内容估算高（不含壳层底距；顶距媒体为 0）。
    static let minContentHeight: CGFloat = 152

    static func panelSize() -> CGSize {
        CGSize(
            width: contentWidth + IslandChrome.horizontalInsetTotal,
            height: minContentHeight + IslandChrome.contentBottom
        )
    }
}

/// 设置预览边距：收起贴真岛；展开顶距用「可见」inset（预览无刘海盲区，勿照搬真岛顶 0）。
enum MediaPreviewChrome {
    /// 收起态左右内边距（与真岛 `padding(.horizontal, 10)` 相同）。
    static let compactHorizontal: CGFloat = 10
    /// 收起态内容框高（预览用参考刘海高）；真机由 IslandContentView 按实时刘海算。
    static var compactContentHeight: CGFloat {
        max(0, NotchGeometry.compactPanelHeight(notchHeight: NotchGeometry.compactIslandHeight) - 4)
    }
    /// 展开态预览顶距：无硬件遮挡，留一小段可见空隙；禁止用 0（顶贴黑边），也禁止照搬含盲区的 `expandedTopInset`。
    static var expandedTop: CGFloat {
        IslandChrome.previewExpandedVisibleTopInset()
    }
    static var expandedBottom: CGFloat { IslandChrome.contentBottom }
    static var expandedHorizontal: CGFloat { IslandChrome.contentHorizontal }
}

/// 媒体岛卡：设置预览与岛上真机共用。
/// 顶行与刘海同高：左封面、右律动；其下歌名左 / 作者右同一行。
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
    /// 设置预览无真刘海时的占位宽。
    var previewNotchWidth: CGFloat = 110
    var previewNotchHeight: CGFloat = 32

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    /// 点击后立刻翻转，不等 MediaRemote 回写（否则暂停图标会顿一下）。
    @State private var optimisticPlaying: Bool? = nil

    private var shownProgress: Double {
        isDragging ? dragProgress : min(max(progress, 0), 1)
    }

    private var shownPlaying: Bool {
        optimisticPlaying ?? isPlaying
    }

    private var notchWidth: CGFloat {
        envNotchWidth > 40 ? envNotchWidth : previewNotchWidth
    }

    private var notchHeight: CGFloat {
        envNotchHeight > 10 ? envNotchHeight : previewNotchHeight
    }

    /// 封面边长贴合刘海高度，避免翼行高于刘海。
    private var artworkSide: CGFloat {
        min(32, max(26, notchHeight - 4))
    }

    private let coral = Color(red: 1.0, green: 0.42, blue: 0.29) // #ff6b4a
    private let coralRose = Color(red: 1.0, green: 0.45, blue: 0.26) // #ff7243
    private let appleMusicRed = Color(red: 0.99, green: 0.24, blue: 0.27) // #fc3c44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 与刘海同线：左封面 · 中空刘海宽 · 右律动（固定中空，避免 Spacer 撑破命中框）。
            HStack(alignment: .center, spacing: 0) {
                artworkView
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: min(notchWidth, MediaExpandedContentSize.contentWidth * 0.55))
                MediaAudioEqualizerView(isPlaying: shownPlaying, tint: coral, animated: animatedEqualizer)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(height: max(artworkSide, 28))

            // 歌名左、作者右，同一行。
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(artist.isEmpty ? " " : artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            VStack(spacing: 6) {
                progressBar

                // AppKit 按钮 + 按下缩放/闪白；播放态乐观翻转。
                HStack(spacing: 22) {
                    transportButton(
                        symbol: "backward.fill",
                        diameter: 32,
                        pointSize: 14,
                        foreground: .white.withAlphaComponent(0.85),
                        background: .clear,
                        label: L10n.Media.previousA11y,
                        action: onPrevious
                    )
                    transportButton(
                        symbol: shownPlaying ? "pause.fill" : "play.fill",
                        diameter: 36,
                        pointSize: 15,
                        foreground: .black,
                        background: .white,
                        label: shownPlaying ? L10n.Media.pauseA11y : L10n.Media.playA11y,
                        action: {
                            optimisticPlaying = !shownPlaying
                            AppLog.info("Media", "播放按钮乐观翻转", ["nextPlaying": optimisticPlaying ?? false])
                            onTogglePlay?()
                        }
                    )
                    transportButton(
                        symbol: "forward.fill",
                        diameter: 32,
                        pointSize: 14,
                        foreground: .white.withAlphaComponent(0.85),
                        background: .clear,
                        label: L10n.Media.nextA11y,
                        action: onNext
                    )
                }
                .frame(maxWidth: .infinity)
                .zIndex(2)
            }
        }
        .frame(width: MediaExpandedContentSize.contentWidth)
        .onChange(of: isPlaying) { _, newValue in
            // 系统态追上乐观态后清掉；若不一致以系统为准。
            if optimisticPlaying == nil { return }
            if optimisticPlaying == newValue {
                optimisticPlaying = nil
            } else {
                optimisticPlaying = nil
            }
        }
    }

    @ViewBuilder
    private func transportButton(
        symbol: String,
        diameter: CGFloat,
        pointSize: CGFloat,
        foreground: NSColor,
        background: NSColor,
        label: String,
        action: (() -> Void)?
    ) -> some View {
        let isSolid = background.alphaComponent > 0.05
        ZStack {
            // 白底正圆交给 SwiftUI，避免 NSView 被拉扁后 cornerRadius 看起来像椭圆。
            if isSolid {
                Circle()
                    .fill(Color(nsColor: background))
                    .frame(width: diameter, height: diameter)
            }
            MediaTransportAppKitButton(
                symbolName: symbol,
                pointSize: pointSize,
                diameter: diameter,
                foreground: foreground,
                background: .clear,
                accessibilityLabel: label,
                action: { action?() }
            )
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .contentShape(Circle())
    }

    private var artworkView: some View {
        let side = artworkSide
        let corner = max(6, side * 0.22)
        let badge = max(11, side * 0.36)
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.36, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.40), radius: 4, y: 1)

            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: badge, height: badge)
                    .padding(1)
                    .background(
                        RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                    )
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
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

// MARK: - AppKit 播放控件（岛上首击可靠）

/// 暂停 / 切歌：`NSButton` + 按下缩放闪白；避免 `NSHostingView` 吞掉 SwiftUI 首击。
private struct MediaTransportAppKitButton: NSViewRepresentable {
    let symbolName: String
    let pointSize: CGFloat
    let diameter: CGFloat
    let foreground: NSColor
    let background: NSColor
    let accessibilityLabel: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> MediaTransportNSButton {
        let button = MediaTransportNSButton(diameter: diameter)
        button.target = context.coordinator
        button.action = #selector(Coordinator.tap(_:))
        context.coordinator.button = button
        button.apply(
            symbolName: symbolName,
            pointSize: pointSize,
            foreground: foreground,
            background: background,
            accessibilityLabel: accessibilityLabel
        )
        return button
    }

    func updateNSView(_ button: MediaTransportNSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.button = button
        button.apply(
            symbolName: symbolName,
            pointSize: pointSize,
            foreground: foreground,
            background: background,
            accessibilityLabel: accessibilityLabel
        )
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        weak var button: MediaTransportNSButton?
        init(action: @escaping () -> Void) { self.action = action }

        @objc func tap(_ sender: Any?) {
            AppLog.info("Media", "AppKit 播放控件已点击")
            button?.playTapFeedback()
            action()
        }
    }
}

private final class MediaTransportNSButton: NSButton {
    private let diameter: CGFloat
    private var baseBackground = NSColor.clear
    private var currentSymbol = ""
    private var isPressing = false

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = true
        imagePosition = .imageOnly
        // 自绘正中图标，禁止再缩放，否则 pause 易偏心。
        imageScaling = .scaleNone
        (cell as? NSButtonCell)?.highlightsBy = []
        (cell as? NSButtonCell)?.showsStateBy = []
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }

    override func layout() {
        super.layout()
        // 锁正方形；白底圆由 SwiftUI Circle 提供，这里不再改 anchor（改锚易显椭圆）。
        if abs(bounds.width - diameter) > 0.5 || abs(bounds.height - diameter) > 0.5 {
            setFrameSize(NSSize(width: diameter, height: diameter))
        }
        layer?.cornerRadius = 0
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        setPressed(false)
        super.mouseUp(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setPressed(false)
        super.mouseExited(with: event)
    }

    /// 点击回弹：略缩 + 半透明，松手弹回。
    func playTapFeedback() {
        setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            self?.setPressed(false)
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard isPressing != pressed else { return }
        isPressing = pressed
        // 只用透明度，不用 layer scale（scale + 非正方 bounds 会显成椭圆）。
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = pressed ? 0.05 : 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = pressed ? 0.55 : 1.0
        }
        if baseBackground.alphaComponent <= 0.05 {
            layer?.backgroundColor = pressed
                ? NSColor.white.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
        }
    }

    func apply(
        symbolName: String,
        pointSize: CGFloat,
        foreground: NSColor,
        background: NSColor,
        accessibilityLabel: String
    ) {
        baseBackground = background
        // 仅符号变化时换图，避免每帧 apply 打断按下动画。
        if currentSymbol != symbolName {
            currentSymbol = symbolName
            image = Self.makeCenteredIcon(
                symbolName: symbolName,
                canvas: diameter,
                pointSize: pointSize,
                foreground: foreground
            )
        }
        contentTintColor = nil
        layer?.masksToBounds = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.transform = CATransform3DIdentity
        if !isPressing {
            alphaValue = 1
        }
        layer?.shadowOpacity = 0
        toolTip = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
    }

    /// 在 diameter×diameter 画布上几何居中画播放控件图标。
    private static func makeCenteredIcon(
        symbolName: String,
        canvas: CGFloat,
        pointSize: CGFloat,
        foreground: NSColor
    ) -> NSImage {
        let size = NSSize(width: canvas, height: canvas)
        return NSImage(size: size, flipped: false) { rect in
            foreground.setFill()
            switch symbolName {
            case "pause.fill":
                // 紧凑双杠（Apple Music 风格）：杠细、间距窄，避免「猪鼻子」。
                let barW = canvas * 0.11
                let barH = canvas * 0.36
                let gap = canvas * 0.065
                let totalW = barW * 2 + gap
                let x0 = rect.midX - totalW / 2
                let y0 = rect.midY - barH / 2
                let radius = min(barW / 2, 1.6)
                NSBezierPath(
                    roundedRect: NSRect(x: x0, y: y0, width: barW, height: barH),
                    xRadius: radius,
                    yRadius: radius
                ).fill()
                NSBezierPath(
                    roundedRect: NSRect(x: x0 + barW + gap, y: y0, width: barW, height: barH),
                    xRadius: radius,
                    yRadius: radius
                ).fill()
            case "play.fill":
                // 三角略右移光学中心（尖端朝右时视觉偏左）。
                let w = canvas * 0.30
                let h = canvas * 0.36
                let ox = rect.midX - w / 2 + canvas * 0.03
                let oy = rect.midY - h / 2
                let path = NSBezierPath()
                path.move(to: NSPoint(x: ox, y: oy))
                path.line(to: NSPoint(x: ox, y: oy + h))
                path.line(to: NSPoint(x: ox + w, y: oy + h / 2))
                path.close()
                path.fill()
            case "backward.fill", "forward.fill":
                let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [foreground]))
                if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let side = min(canvas * 0.48, pointSize * 1.25)
                    let iconRect = NSRect(
                        x: rect.midX - side / 2,
                        y: rect.midY - side / 2,
                        width: side,
                        height: side
                    )
                    symbol.draw(
                        in: iconRect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1,
                        respectFlipped: true,
                        hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
                    )
                }
            default:
                break
            }
            return true
        }
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
