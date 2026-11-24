import SwiftUI

/// 隔空投送接收完成 tip：左图标+「隔空投送」/ 右文件名；整卡可点打开。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding。
struct AirDropReceiveNoticeCard: View {
    let notice: AirDropReceiveNotice
    var compact: Bool = false
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110
    var onOpen: (() -> Void)? = nil

    static let liveWingWidth: CGFloat = IslandChrome.preparedWingWidth

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.90)
    private let iconSide: CGFloat = 16
    private let leftClusterSpacing: CGFloat = IslandFlushWingStyle.iconLabelSpacing

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        if flushSide != nil { return IslandFlushWingStyle.height }
        if compact { return 30 }
        return max(envNotchHeight, 32)
    }

    private var wingWidth: CGFloat { compact ? 90 : Self.liveWingWidth }
    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    private var titleBudget: CGFloat {
        max(0, wingWidth - iconSide - leftClusterSpacing)
    }

    private var isPeninsula: Bool { flushSide != nil }

    static func previewSample(
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil,
        includeChrome: Bool = true
    ) -> some View {
        let notice = AirDropReceiveNotice(
            id: "preview.airdrop",
            path: "/tmp/Photo.jpg",
            fileName: "Photo.jpg"
        )
        let card = AirDropReceiveNoticeCard(
            notice: notice,
            compact: true,
            flushSide: flushSide,
            bareWingContent: false
        )
        if let flushSide {
            return AnyView(
                IslandFlushWingCapsule(side: flushSide, width: IslandChrome.dualFlushCompactWingWidth) {
                    card
                }
            )
        }
        _ = includeChrome
        return AnyView(card)
    }

    var body: some View {
        Group {
            if isPeninsula {
                peninsulaBody
            } else {
                fullBody
            }
        }
        .frame(width: isPeninsula ? nil : totalWidth, height: barHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onOpen {
                onOpen()
            } else {
                _ = AirDropReceiveSession.shared.handleClick()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.AirDropReceive.tipTitle)，\(notice.fileName)")
        .accessibilityHint(L10n.AirDropReceive.tapToOpen)
        .accessibilityAddTraits(.isButton)
    }

    private var fullBody: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wingWidth, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            rightWing
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(width: totalWidth, height: barHeight)
    }

    private var peninsulaBody: some View {
        HStack(spacing: leftClusterSpacing) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text(notice.fileName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .modifier(BareOrPlainWing(bare: bareWingContent))
    }

    private var leftWing: some View {
        HStack(spacing: leftClusterSpacing) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: iconSide, height: iconSide)
            Text(L10n.AirDropReceive.tipTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .frame(maxWidth: titleBudget, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rightWing: some View {
        Text(notice.fileName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

private struct BareOrPlainWing: ViewModifier {
    var bare: Bool

    func body(content: Content) -> some View {
        if bare {
            content.islandBareFlushWingContent()
        } else {
            content
        }
    }
}
