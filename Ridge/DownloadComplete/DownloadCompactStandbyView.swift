import AppKit
import SwiftUI

/// 下载常驻（产品 **C**，同档内高于计时）：
/// - **全岛**（单独）：方案 04——进行中图标+名 / 定宽估速+微圆环；完成勾+名 / AppKit「打开」
/// - **半岛**（并排半翼）：左文件名 · 右薄荷绿估速；底边进度；悬停 morph「打开」
/// 根视图不加外圈 padding。
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
    @State private var localHover = false

    private let downloadAccent = Color(red: 0.678, green: 0.776, blue: 1.0)
    private let checkGreen = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let speedGreen = IslandFlushWingStyle.accentSuccess
    private let iconSide: CGFloat = 14
    private let leftClusterSpacing: CGFloat = IslandFlushWingStyle.iconLabelSpacing
    /// 全岛右翼速度列定宽，避免 `MB/s` 文案长短拽翼宽。
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

    private var showsPeninsulaOpenMorph: Bool {
        flushSide != nil && localHover
    }

    var body: some View {
        Group {
            if flushSide != nil {
                peninsulaBody
                    .onHover { hovering in
                        if localHover != hovering {
                            localHover = hovering
                            AppLog.debug("Download", "下载半岛悬停", [
                                "hover": hovering,
                                "phase": phase.rawValue
                            ])
                        }
                    }
                    .animation(.easeOut(duration: 0.18), value: showsPeninsulaOpenMorph)
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

    // MARK: - 半岛（半翼）

    private var peninsulaBody: some View {
        let side = flushSide ?? .trailing
        let shape = IslandFlushWingStyle.capsuleShape(side: side)
        let stack = ZStack {
            peninsulaIdleLayer
                .opacity(showsPeninsulaOpenMorph ? 0 : 1)
                .scaleEffect(showsPeninsulaOpenMorph ? 0.95 : 1)
                .allowsHitTesting(!showsPeninsulaOpenMorph)
            peninsulaOpenMorphLayer
                .opacity(showsPeninsulaOpenMorph ? 1 : 0)
                .scaleEffect(showsPeninsulaOpenMorph ? 1 : 0.95)
                .allowsHitTesting(showsPeninsulaOpenMorph)
        }

        if bareWingContent {
            return AnyView(
                stack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if showsPeninsulaOpenMorph {
                            speedGreen.opacity(0.22)
                        }
                    }
                    .clipShape(shape)
            )
        }
        return AnyView(
            stack
                .frame(width: IslandFlushWingStyle.width, height: IslandFlushWingStyle.height)
                .background(
                    shape.fill(showsPeninsulaOpenMorph ? speedGreen.opacity(0.22) : Color.black)
                )
                .clipShape(shape)
        )
    }

    private var peninsulaIdleLayer: some View {
        let row = HStack(spacing: 0) {
            Text(fileName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            peninsulaIdleTrailing
        }
        return ZStack(alignment: .bottom) {
            Group {
                if bareWingContent {
                    row.islandBareFlushWingContent()
                } else {
                    row.padding(.horizontal, IslandFlushWingStyle.horizontalPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if phase == .downloading {
                DownloadPeninsulaProgressBar(fraction: progressFraction)
                    .frame(height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: performTap)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var peninsulaIdleTrailing: some View {
        switch phase {
        case .downloading:
            Text(speedLabel ?? "0 KB/s")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(speedGreen)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(checkGreen)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var peninsulaOpenMorphLayer: some View {
        if onTap != nil {
            openBadgeChrome(title: L10n.DownloadComplete.openBadge, showShortcut: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        } else {
            DownloadOpenAppKitButton(
                title: L10n.DownloadComplete.openBadge,
                shortcut: nil
            ) {
                AppLog.warn("Download", "AppKit 打开按钮已点击")
                performTap()
            }
            .frame(height: DownloadOpenAppKitButton.fixedHeight)
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 全岛

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

                fullIslandRightWing(width: wing)
            }
            .frame(width: total, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func fullIslandRightWing(width: CGFloat) -> some View {
        if phase == .downloading {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                fullIslandTrailingStatus
            }
            .frame(width: width, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture(perform: performTap)
        } else {
            // 完成态禁止 SwiftUI tap 盖住 AppKit「打开」。
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                fullIslandTrailingStatus
            }
            .frame(width: width, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var fullIslandTrailingStatus: some View {
        switch phase {
        case .completed:
            openBadge
        case .downloading:
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
            openBadgeChrome(title: L10n.DownloadComplete.openBadge, showShortcut: showsOpenShortcutChip)
                .allowsHitTesting(false)
        } else {
            DownloadOpenAppKitButton(
                title: L10n.DownloadComplete.openBadge,
                shortcut: showsOpenShortcutChip ? openShortcutLabel : nil
            ) {
                AppLog.warn("Download", "AppKit 打开按钮已点击")
                performTap()
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
        fileName: String = "Docker.raw",
        phase: DownloadIslandPhase = .completed,
        speedBytesPerSecond: Double? = nil,
        progressFraction: Double? = nil,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        let card = DownloadCompactStandbyView(
            fileName: fileName,
            phase: phase,
            speedBytesPerSecond: speedBytesPerSecond,
            progressFraction: progressFraction ?? (phase == .downloading ? 0.82 : nil),
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

// MARK: - Peninsula progress

private struct DownloadPeninsulaProgressBar: View {
    var fraction: Double?

    private let blue = Color(red: 0.15, green: 0.45, blue: 0.95)
    private let cyan = Color(red: 0.25, green: 0.85, blue: 0.85)
    private let green = IslandFlushWingStyle.accentSuccess

    @State private var indeterminatePhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: w, height: h)
                if let fraction, fraction >= 0 {
                    let fill = min(1, max(0.04, fraction))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [blue, cyan, green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * fill, height: h)
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [blue.opacity(0.2), cyan, green.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * 0.28, height: h)
                        .offset(x: (w - w * 0.28) * indeterminatePhase)
                }
            }
            .frame(width: w, height: h)
            .clipShape(Capsule())
        }
        .onAppear {
            guard fraction == nil else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: true)) {
                indeterminatePhase = 1
            }
        }
    }
}

// MARK: - AppKit Open

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        AppLog.warn("Download", "AppKit 打开 mouseDown", [
            "w": Int(bounds.width),
            "h": Int(bounds.height)
        ])
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

// MARK: - Full-island ring

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
