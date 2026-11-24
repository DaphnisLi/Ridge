import AppKit
import SwiftUI

/// 下载常驻小岛（方案 04）：
/// - 进行中：左下载图标+文件名；右 16px 微圆环 + **定宽**估速
/// - 完成：左绿色勾+文件名；右 AppKit「打开」徽章（可点 / 设置快捷键）；约 3s 自动撤，悬停续命
/// 根视图不加外圈 padding（壳层 `IslandChrome` 管边距）。
struct DownloadCompactStandbyView: View {
    let fileName: String
    var phase: DownloadIslandPhase = .completed
    var speedBytesPerSecond: Double? = nil
    var progressFraction: Double? = nil
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110
    var onTap: (() -> Void)? = nil

    @ObservedObject private var downloadSettings = DownloadCompleteSettings.shared
    @Environment(\.islandNotchWidth) private var envNotchWidth

    private let downloadAccent = Color(red: 0.678, green: 0.776, blue: 1.0)
    private let checkGreen = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let iconSide: CGFloat = 14
    private let leftClusterSpacing: CGFloat = IslandFlushWingStyle.iconLabelSpacing
    /// 右翼速度列定宽，避免 `12.3 MB/s` ↔ `128 KB/s` 拽动整岛/翼宽。
    private static let speedColumnWidth: CGFloat = 78

    private var notchWidth: CGFloat {
        envNotchWidth > 40 ? envNotchWidth : previewNotchWidth
    }

    private var speedLabel: String? {
        guard phase == .downloading else { return nil }
        return DownloadTransferFormatting.speedText(bytesPerSecond: speedBytesPerSecond)
    }

    private var showsOpenShortcutChip: Bool {
        flushSide == nil && downloadSettings.keyboardShortcutEnabled
    }

    private var openShortcutLabel: String {
        downloadSettings.hotKey.displayString
    }

    var body: some View {
        Group {
            if flushSide != nil {
                // 完成态右翼 AppKit「打开」：禁止整翼 onTap 盖住（空 guard 也会抢命中）。
                peninsulaBody
            } else {
                fullStandbyBody
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(
            phase == .downloading
                ? L10n.DownloadComplete.tapHintDownloading
                : L10n.DownloadComplete.tapHint
        )
    }

    private func performTap() {
        if let onTap {
            onTap()
        } else {
            _ = DownloadCompleteSession.shared.handleClick()
        }
    }

    private var accessibilityTitle: String {
        if phase == .downloading {
            if let speedLabel {
                return "\(L10n.DownloadComplete.downloadingBadge)，\(fileName)，\(speedLabel)"
            }
            return "\(L10n.DownloadComplete.downloadingBadge)，\(fileName)"
        }
        return "\(L10n.DownloadComplete.openBadge)，\(fileName)"
    }

    private var peninsulaBody: some View {
        let row = HStack(spacing: 0) {
            HStack(spacing: leftClusterSpacing) {
                leadIcon
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: performTap)
            .accessibilityAddTraits(.isButton)

            if phase == .downloading {
                Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: performTap)
                trailingStatus
                    .contentShape(Rectangle())
                    .onTapGesture(perform: performTap)
            } else {
                // 完成态：Spacer 不抢点；右翼仅 AppKit「打开」（对齐会议满岛入会钮）。
                Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
                    .allowsHitTesting(false)
                trailingStatus
            }
        }
        if bareWingContent {
            return AnyView(row.islandBareFlushWingContent())
        }
        return AnyView(IslandFlushWingCapsule(side: flushSide ?? .leading) { row })
    }

    private var fullStandbyBody: some View {
        GeometryReader { geo in
            let total = max(geo.size.width, 1)
            let notch = min(max(notchWidth, 1), total * 0.72)
            let wing = max(0, (total - notch) / 2)
            let titleBudget = max(0, wing - iconSide - leftClusterSpacing)
            HStack(spacing: 0) {
                HStack(spacing: leftClusterSpacing) {
                    leadIcon
                        .frame(width: iconSide)
                    IslandCompactTitleMarquee(
                        text: fileName,
                        animated: true,
                        visibleWidth: titleBudget,
                        fontSize: 13,
                        fontWeight: .semibold,
                        foreground: Color.white.opacity(0.95),
                        logTag: "Download"
                    )
                }
                .frame(width: wing, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: performTap)
                .accessibilityAddTraits(.isButton)

                Color.clear
                    .frame(width: notch)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: performTap)
                    .accessibilityHidden(true)

                rightWing(width: wing)
            }
            .frame(width: total, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func rightWing(width: CGFloat) -> some View {
        if phase == .downloading {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                trailingStatus
            }
            .frame(width: width, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture(perform: performTap)
        } else {
            // 完成态禁止任何 SwiftUI tap / contentShape 盖住 AppKit「打开」。
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                trailingStatus
            }
            .frame(width: width, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        switch phase {
        case .completed:
            openBadge
        case .downloading:
            // 靠右：速度（定宽）在左，进度环在右。
            HStack(spacing: 6) {
                Text(speedLabel ?? "0 KB/s")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .opacity(speedLabel == nil ? 0 : 1)
                    .frame(width: Self.speedColumnWidth, alignment: .trailing)
                    .accessibilityHidden(speedLabel == nil)
                DownloadMicroGaugeRing(
                    progress: progressFraction,
                    tint: downloadAccent
                )
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var openBadge: some View {
        if onTap != nil {
            // 预览 / 图鉴：不接真 Session。
            openBadgeChrome(title: L10n.DownloadComplete.openBadge, showShortcut: showsOpenShortcutChip)
                .allowsHitTesting(false)
        } else {
            DownloadOpenAppKitButton(
                title: L10n.DownloadComplete.openBadge,
                shortcut: showsOpenShortcutChip ? openShortcutLabel : nil
            ) {
                AppLog.warn("Download", "AppKit 打开按钮已点击")
                _ = DownloadCompleteSession.shared.handleClick()
            }
            .frame(height: DownloadOpenAppKitButton.fixedHeight)
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(1)
        }
    }

    private func openBadgeChrome(title: String, showShortcut: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
            if showShortcut {
                Text(openShortcutLabel)
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.25), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(red: 0.0, green: 0.431, blue: 0.157), in: Capsule())
    }

    private var leadIcon: some View {
        Group {
            if phase == .downloading {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(downloadAccent)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(checkGreen)
            }
        }
        .accessibilityHidden(true)
    }

    static func previewSample(
        fileName: String = "Report.pdf",
        phase: DownloadIslandPhase = .completed,
        speedBytesPerSecond: Double? = nil,
        progressFraction: Double? = nil,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        let card = DownloadCompactStandbyView(
            fileName: fileName,
            phase: phase,
            speedBytesPerSecond: speedBytesPerSecond,
            progressFraction: progressFraction ?? (phase == .downloading ? 0.62 : nil),
            flushSide: flushSide,
            bareWingContent: false,
            onTap: {}
        )
        if let flushSide {
            return AnyView(
                IslandFlushWingCapsule(side: flushSide, width: IslandChrome.dualFlushCompactWingWidth) {
                    card
                }
            )
        }
        return AnyView(
            card
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: 34)
        )
    }
}

extension DownloadCompactStandbyView {
    init(
        item: DownloadCompleteItem,
        flushSide: IslandFlushWingStyle.Side? = nil,
        bareWingContent: Bool = false,
        previewNotchWidth: CGFloat = 110,
        onTap: (() -> Void)? = nil
    ) {
        self.init(
            fileName: item.fileName,
            phase: item.phase,
            speedBytesPerSecond: item.speedBytesPerSecond,
            progressFraction: item.progressFraction,
            flushSide: flushSide,
            bareWingContent: bareWingContent,
            previewNotchWidth: previewNotchWidth,
            onTap: onTap
        )
    }
}

/// 完成态「打开」：AppKit 钮，避开 nonactivatingPanel 上 SwiftUI 首击失灵。
private struct DownloadOpenAppKitButton: NSViewRepresentable {
    let title: String
    var shortcut: String?
    let action: () -> Void

    static let fixedHeight: CGFloat = 22

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> DownloadOpenNSButton {
        let button = DownloadOpenNSButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.tap(_:))
        button.apply(title: title, shortcut: shortcut)
        return button
    }

    func updateNSView(_ button: DownloadOpenNSButton, context: Context) {
        context.coordinator.action = action
        button.apply(title: title, shortcut: shortcut)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func tap(_ sender: Any?) {
            action()
        }
    }
}

private final class DownloadOpenNSButton: NSButton {
    private let fixedHeight = DownloadOpenAppKitButton.fixedHeight

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryLight)
        isEnabled = true
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = true
        (cell as? NSButtonCell)?.highlightsBy = []
        (cell as? NSButtonCell)?.showsStateBy = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(title: String, shortcut: String?) {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let shortcutFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
        )
        if let shortcut, !shortcut.isEmpty {
            text.append(NSAttributedString(string: "  "))
            let chip = NSMutableAttributedString(
                string: " \(shortcut) ",
                attributes: [
                    .font: shortcutFont,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                    .backgroundColor: NSColor.black.withAlphaComponent(0.25),
                ]
            )
            text.append(chip)
        }
        attributedTitle = text
        layer?.backgroundColor = NSColor(red: 0, green: 0.431, blue: 0.157, alpha: 1).cgColor
        layer?.cornerRadius = fixedHeight / 2
        contentTintColor = .white
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let titleSize = attributedTitle.size()
        return NSSize(
            width: ceil(titleSize.width) + 20,
            height: fixedHeight
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 整颗胶囊 bounds 都可点，不限于文字字形（对齐会议入会钮）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        AppLog.warn("Download", "AppKit 打开 mouseDown", [
            "w": Int(bounds.width),
            "h": Int(bounds.height)
        ])
        // 不走 super：避免 cell 与 SwiftUI 宿主抢首击；mouseUp 再 performClick。
        highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        highlight(false)
        let local = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(local)
        AppLog.warn("Download", "AppKit 打开 mouseUp", [
            "inside": inside,
            "w": Int(bounds.width),
            "h": Int(bounds.height)
        ])
        if inside {
            performClick(nil)
        }
    }
}

/// 右翼微圆环：画布略大于描边，避免上下被裁。
private struct DownloadMicroGaugeRing: View {
    var progress: Double?
    var tint: Color

    private let ringSize: CGFloat = 14
    private let lineWidth: CGFloat = 2.0
    private var canvas: CGFloat { ringSize + lineWidth }

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)
            if let progress, progress >= 0 {
                Circle()
                    .trim(from: 0, to: min(1, max(0.05, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(
                        .linear(duration: 1.1).repeatForever(autoreverses: false),
                        value: spin
                    )
                    .onAppear { spin = true }
            }
            Circle()
                .fill(tint)
                .frame(width: 3, height: 3)
        }
        .frame(width: canvas, height: canvas)
        .accessibilityHidden(true)
    }
}
