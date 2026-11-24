import SwiftUI

/// 网络 / VPN 瞬时 tip：满岛左图标+名称 / 右延迟或「断开」+发光点；
/// 半岛仅图标+名称（连接绿 / 断开红，名称白）。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding；翼宽对齐 `preparedNetworkLinkWingWidth`。
struct NetworkLinkNoticeCard: View {
    let notice: NetworkLinkNotice
    var compact: Bool = false
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110

    /// 真岛满岛翼宽；须与 `IslandChrome.preparedNetworkLinkWingWidth` 同值（自动化锁）。
    static let liveWingWidth: CGFloat = IslandChrome.preparedNetworkLinkWingWidth

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

    /// 库卡 compact 翼宽：与 `SettingsIslandPreviewWidth.library`（290）对齐（90×2+110）。
    private var wingWidth: CGFloat { compact ? 90 : Self.liveWingWidth }
    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    /// 左翼名称可用宽（图标 + 间距已扣）。
    private var titleBudget: CGFloat {
        max(0, wingWidth - iconSide - leftClusterSpacing)
    }

    /// Wi‑Fi / VPN 断开态。
    private var isDisconnect: Bool {
        switch notice.kind {
        case .wifiDisconnected, .vpnDisconnected: return true
        default: return false
        }
    }

    /// 满岛左翼图标：连接白 / 断开红。
    private var fullWingIconColor: Color {
        isDisconnect ? IslandFlushWingStyle.accentDanger : Color.white.opacity(0.95)
    }

    /// 半岛图标：连接绿 / 断开红。
    private var peninsulaIconColor: Color {
        isDisconnect ? IslandFlushWingStyle.accentDanger : IslandFlushWingStyle.accentSuccess
    }

    /// 名称始终白。
    private var titleColor: Color { Color.white.opacity(0.95) }

    /// 连接态：延迟字与点同色（低延迟绿 / 过高黄）；断开：「断开」白字，点仍红。
    private var detailColor: Color {
        if isDisconnect { return Color.white.opacity(0.92) }
        return latencyAccent
    }

    private var dotColor: Color {
        if isDisconnect { return IslandFlushWingStyle.accentDanger }
        return latencyAccent
    }

    private var latencyAccent: Color {
        switch NetworkLinkMetrics.latencyTone(ms: notice.latencyMs) {
        case .elevated:
            return IslandFlushWingStyle.accentWarning
        case .good, .unknown:
            return IslandFlushWingStyle.accentSuccess
        }
    }

    private var symbol: String? {
        switch notice.kind {
        case .wifiConnected: return "wifi"
        case .wiredConnected: return nil // 自定义 `<···>`，见 `NetworkLinkWiredIcon`
        case .vpnConnected, .vpnDisconnected: return "shield"
        case .wifiDisconnected: return "wifi.slash"
        }
    }

    private var accessibilityText: String {
        if let detail = notice.detail, !detail.isEmpty {
            return "\(notice.title)，\(detail)"
        }
        return notice.title
    }

    private var isPeninsula: Bool { flushSide != nil }

    static func previewSample(
        kind: NetworkLinkTipKind,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil,
        includeChrome: Bool = true
    ) -> some View {
        let notice = previewNotice(kind: kind)
        let card = NetworkLinkNoticeCard(
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
        guard includeChrome else { return AnyView(card) }
        return AnyView(
            card
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: SettingsIslandPreviewWidth.tipDetailMinHeight)
        )
    }

    /// 设置 / 图鉴假数据（对齐稿面；网速位一律延迟）。
    static func previewNotice(kind: NetworkLinkTipKind) -> NetworkLinkNotice {
        switch kind {
        case .wifiConnected:
            return NetworkLinkNotice(
                id: "preview.network.wifiConnected",
                kind: .wifiConnected,
                title: "AirNet",
                detail: "18ms",
                ssid: "AirNet",
                latencyMs: 18
            )
        case .wiredConnected:
            return NetworkLinkNotice(
                id: "preview.network.wiredConnected",
                kind: .wiredConnected,
                title: L10n.NetworkLink.wiredShort,
                detail: "12ms",
                latencyMs: 12
            )
        case .wifiDisconnected:
            return NetworkLinkNotice(
                id: "preview.network.wifiDisconnected",
                kind: .wifiDisconnected,
                title: "AirNet",
                detail: L10n.NetworkLink.disconnectedBadge,
                ssid: "AirNet"
            )
        case .vpnDisconnected:
            return NetworkLinkNotice(
                id: "preview.network.vpnDisconnected",
                kind: .vpnDisconnected,
                title: "Tokyo-04",
                detail: L10n.NetworkLink.disconnectedBadge
            )
        case .vpnConnected:
            // 与断开态同布局：盾牌 + 名称；右翼延迟 + 绿点。
            return NetworkLinkNotice(
                id: "preview.network.vpnConnected",
                kind: .vpnConnected,
                title: "Tokyo-04",
                detail: "24ms",
                latencyMs: 24
            )
        }
    }

    var body: some View {
        Group {
            if isPeninsula {
                peninsulaBody
            } else {
                fullWingBody
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var fullWingBody: some View {
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth, alignment: .leading)
                .clipped()
            Color.clear
                .frame(width: notchWidth)
                .accessibilityHidden(true)
            rightCluster
                .frame(width: wingWidth, alignment: .trailing)
                .clipped()
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
    }

    /// 半岛：仅图标+名称；连接绿图标 / 断开红图标；名称白；对齐其它 tip 的 bare 左右内边距。
    @ViewBuilder
    private var peninsulaBody: some View {
        let row = GeometryReader { geo in
            let nameBudget = max(0, geo.size.width - iconSide - leftClusterSpacing)
            HStack(spacing: leftClusterSpacing) {
                leadIcon(color: peninsulaIconColor)
                    .frame(width: iconSide, alignment: .center)
                    .layoutPriority(1)
                IslandCompactTitleMarquee(
                    text: notice.title,
                    animated: true,
                    visibleWidth: nameBudget,
                    fontSize: compact ? 12 : 13,
                    fontWeight: .semibold,
                    foreground: titleColor,
                    logTag: "NetworkLink"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        if bareWingContent {
            row.islandBareFlushWingContent()
        } else {
            row
        }
    }

    private var leftCluster: some View {
        HStack(spacing: leftClusterSpacing) {
            leadIcon(color: fullWingIconColor)
                .frame(width: iconSide, alignment: .center)
                .layoutPriority(1)
            IslandCompactTitleMarquee(
                text: notice.title,
                animated: true,
                visibleWidth: titleBudget,
                fontSize: compact ? 12 : 13,
                fontWeight: .semibold,
                foreground: titleColor,
                logTag: "NetworkLink"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func leadIcon(color: Color) -> some View {
        if notice.kind == .wiredConnected {
            NetworkLinkWiredIcon(color: color, compact: compact)
        } else if let symbol {
            Image(systemName: symbol)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var rightCluster: some View {
        HStack(spacing: 6) {
            if let detail = notice.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(
                        size: compact ? 11 : 12,
                        weight: isDisconnect ? .semibold : .medium,
                        design: .default
                    ))
                    .foregroundStyle(detailColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            NetworkLinkStatusDot(color: dotColor)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 稿面有线图标：`< ··· >`（SF Symbol 无对应字形，自绘）。
struct NetworkLinkWiredIcon: View {
    var color: Color = .white
    var compact: Bool = false

    private var side: CGFloat { compact ? 14 : 16 }
    private var stroke: CGFloat { compact ? 1.6 : 1.85 }
    private var dot: CGFloat { compact ? 1.7 : 2.0 }

    var body: some View {
        Canvas { context, size in
            let midY = size.height * 0.5
            let insetX = size.width * 0.08
            let bracketW = size.width * 0.22
            let bracketH = size.height * 0.62

            // 左 `<`
            var left = Path()
            left.move(to: CGPoint(x: insetX + bracketW, y: midY - bracketH * 0.5))
            left.addLine(to: CGPoint(x: insetX, y: midY))
            left.addLine(to: CGPoint(x: insetX + bracketW, y: midY + bracketH * 0.5))
            context.stroke(left, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))

            // 右 `>`
            var right = Path()
            right.move(to: CGPoint(x: size.width - insetX - bracketW, y: midY - bracketH * 0.5))
            right.addLine(to: CGPoint(x: size.width - insetX, y: midY))
            right.addLine(to: CGPoint(x: size.width - insetX - bracketW, y: midY + bracketH * 0.5))
            context.stroke(right, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))

            // 中间三点
            let span = size.width * 0.34
            let startX = (size.width - span) * 0.5
            for i in 0..<3 {
                let t = CGFloat(i) / 2.0
                let x = startX + span * t
                let r = CGRect(x: x - dot * 0.5, y: midY - dot * 0.5, width: dot, height: dot)
                context.fill(Path(ellipseIn: r), with: .color(color))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// 稿面右侧发光状态点。
struct NetworkLinkStatusDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 10, height: 10)
                .blur(radius: 2.2)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}
