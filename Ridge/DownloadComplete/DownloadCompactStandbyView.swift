import AppKit
import SwiftUI

/// 下载常驻小岛：进行中 = 图标+文件名+估速（无速度/无进度则右翼仅图标）；完成 = 勾选文案。
struct DownloadCompactStandbyView: View {
    let fileName: String
    var phase: DownloadIslandPhase = .completed
    var speedBytesPerSecond: Double? = nil
    var progressFraction: Double? = nil
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110
    var onTap: (() -> Void)? = nil

    @Environment(\.islandNotchWidth) private var envNotchWidth

    private let accent = Color(nsColor: .systemBlue)
    private let iconSide: CGFloat = 16
    private let leftClusterSpacing: CGFloat = IslandFlushWingStyle.iconLabelSpacing

    private var notchWidth: CGFloat {
        envNotchWidth > 40 ? envNotchWidth : previewNotchWidth
    }

    private var speedLabel: String? {
        guard phase == .downloading else { return nil }
        return DownloadTransferFormatting.speedText(bytesPerSecond: speedBytesPerSecond)
    }

    var body: some View {
        Group {
            if flushSide != nil {
                peninsulaBody
            } else {
                fullStandbyBody
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap {
                onTap()
            } else {
                DownloadCompleteSession.shared.handleClick()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(
            phase == .downloading
                ? L10n.DownloadComplete.tapHintDownloading
                : L10n.DownloadComplete.tapHint
        )
    }

    private var accessibilityTitle: String {
        if phase == .downloading {
            if let speedLabel {
                return "\(L10n.DownloadComplete.downloadingBadge)，\(fileName)，\(speedLabel)"
            }
            return "\(L10n.DownloadComplete.downloadingBadge)，\(fileName)"
        }
        return "\(L10n.DownloadComplete.doneBadge)，\(fileName)"
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
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            trailingStatus
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
                Color.clear
                    .frame(width: notch)
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    trailingStatus
                }
                .frame(width: wing, alignment: .trailing)
                .clipped()
            }
            .frame(width: total, height: geo.size.height)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        switch phase {
        case .completed:
            Text(L10n.DownloadComplete.doneBadge)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
        case .downloading:
            // 有估速 → 速度；无总长不画假进度条；再退化 → 仅下载图标。
            if let speedLabel {
                Text(speedLabel)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
            } else if let progressFraction {
                Text("\(Int((progressFraction * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
    }

    private var leadIcon: some View {
        Image(systemName: phase == .downloading ? "arrow.down.circle.fill" : "arrow.down.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .accessibilityHidden(true)
    }

    static func previewSample(
        fileName: String = "Report.pdf",
        phase: DownloadIslandPhase = .completed,
        speedBytesPerSecond: Double? = nil,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        let card = DownloadCompactStandbyView(
            fileName: fileName,
            phase: phase,
            speedBytesPerSecond: speedBytesPerSecond,
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
