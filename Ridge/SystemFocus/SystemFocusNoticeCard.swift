import SwiftUI

/// 系统 Focus tip（C 类）：满岛左图标+名称 / 右「直到」|「已打开」|「已关闭」+指示；
/// 半岛三区：左图标贴名称、中留白、右仅指示（开=模式色实心光点，关=空心暗环）。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding。
struct SystemFocusNoticeCard: View {
    let notice: SystemFocusNotice
    var compact: Bool = false
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110

    static let liveWingWidth: CGFloat = IslandChrome.preparedWingWidth

    private let iconSide: CGFloat = 16
    private let leftClusterSpacing: CGFloat = IslandFlushWingStyle.iconLabelSpacing
    private let indicatorSide: CGFloat = 10

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

    private var wingWidth: CGFloat { compact ? 70 : Self.liveWingWidth }
    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    private var titleBudget: CGFloat {
        max(0, wingWidth - iconSide - leftClusterSpacing)
    }

    private var isOn: Bool { notice.kind == .on }

    /// 模式专属色（开启态图标 / 点；关闭态不用）。
    private var modeAccent: Color {
        SystemFocusPalette.accent(for: notice.tintColorName, active: true)
    }

    private var iconColor: Color {
        isOn ? modeAccent : SystemFocusPalette.offIcon
    }

    private var titleColor: Color {
        isOn ? Color.white.opacity(0.95) : SystemFocusPalette.offTitle
    }

    private var titleWeight: Font.Weight {
        isOn ? .semibold : .regular
    }

    private var detailColor: Color {
        isOn ? modeAccent : SystemFocusPalette.offTitle
    }

    private var isPeninsula: Bool { flushSide != nil }

    static func previewSample(
        kind: SystemFocusTipKind,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        previewSample(
            preview: kind == .on ? .onUntil : .off,
            compact: compact,
            flushSide: flushSide
        )
    }

    static func previewNotice(kind: SystemFocusTipKind) -> SystemFocusNotice {
        previewNotice(preview: kind == .on ? .onUntil : .off)
    }

    /// 设置 / 图鉴：含「直到」与无结束时间的「已打开」。
    enum PreviewVariant: String, CaseIterable {
        case onUntil
        case onOpened
        case off
    }

    static func previewNotice(preview: PreviewVariant) -> SystemFocusNotice {
        switch preview {
        case .onUntil:
            let ends = Calendar.current.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: Date()
            )
            return SystemFocusNotice(
                id: "preview.systemFocus.onUntil",
                kind: .on,
                name: L10n.SystemFocus.fallbackDoNotDisturb,
                symbolImageName: "moon.fill",
                tintColorName: "systemIndigoColor",
                detail: L10n.SystemFocus.untilTime("18:00"),
                endsAt: ends
            )
        case .onOpened:
            // 半岛样张对齐稿：睡眠 + mint。
            return SystemFocusNotice(
                id: "preview.systemFocus.onOpened",
                kind: .on,
                name: L10n.SystemFocus.fallbackSleep,
                symbolImageName: "bed.double.fill",
                tintColorName: "systemMintColor",
                detail: L10n.SystemFocus.openedBadge
            )
        case .off:
            return SystemFocusNotice(
                id: "preview.systemFocus.off",
                kind: .off,
                name: L10n.SystemFocus.fallbackSleep,
                symbolImageName: "bed.double.fill",
                tintColorName: "systemMintColor",
                detail: L10n.SystemFocus.closedBadge
            )
        }
    }

    static func previewSample(
        preview: PreviewVariant,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        let card = SystemFocusNoticeCard(
            notice: previewNotice(preview: preview),
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
        return AnyView(
            card
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: compact ? 34 : 40)
        )
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
        .accessibilityLabel("\(notice.name)，\(notice.detail)")
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

    /// 半岛（方案 03）：左图标贴名称 · 中留白 · 右硬件微点 / 空心环。
    @ViewBuilder
    private var peninsulaBody: some View {
        let row = GeometryReader { geo in
            let nameBudget = max(
                0,
                geo.size.width
                    - iconSide
                    - leftClusterSpacing
                    - indicatorSide
                    - IslandFlushWingStyle.bareContentSpacerMin
            )
            HStack(spacing: 0) {
                HStack(spacing: leftClusterSpacing) {
                    leadIcon
                        .frame(width: iconSide, alignment: .center)
                        .layoutPriority(1)
                    IslandCompactTitleMarquee(
                        text: notice.name,
                        animated: true,
                        visibleWidth: nameBudget,
                        fontSize: compact ? 12 : 13,
                        fontWeight: titleWeight,
                        foreground: titleColor,
                        logTag: "SystemFocus"
                    )
                }
                Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
                SystemFocusStatusIndicator(isOn: isOn, accent: modeAccent)
                    .frame(width: indicatorSide, height: indicatorSide)
                    .layoutPriority(1)
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
            leadIcon
                .frame(width: iconSide, alignment: .center)
                .layoutPriority(1)
            IslandCompactTitleMarquee(
                text: notice.name,
                animated: true,
                visibleWidth: titleBudget,
                fontSize: compact ? 12 : 13,
                fontWeight: titleWeight,
                foreground: titleColor,
                logTag: "SystemFocus"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leadIcon: some View {
        let pointSize: CGFloat = compact ? 13 : 15
        // 关闭态稿面去色而非 slash；自定义 / 私有符号走私有 CoreGlyphs。
        let image = SystemFocusSymbol.nsImage(
            named: notice.symbolImageName,
            pointSize: pointSize,
            fallbacks: ["moon.fill"]
        )
        return Image(nsImage: image)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: pointSize + 1, height: pointSize + 1)
            .foregroundStyle(iconColor)
            .accessibilityHidden(true)
    }

    private var rightCluster: some View {
        HStack(spacing: 6) {
            Text(notice.detail)
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .default))
                .foregroundStyle(detailColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            SystemFocusStatusIndicator(isOn: isOn, accent: modeAccent)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 方案 03：开启=模式色实心微光点；关闭=浅灰空心细环。
private struct SystemFocusStatusIndicator: View {
    let isOn: Bool
    let accent: Color

    var body: some View {
        Group {
            if isOn {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.40))
                        .frame(width: 10, height: 10)
                        .blur(radius: 2.4)
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                }
            } else {
                Circle()
                    .strokeBorder(SystemFocusPalette.offRing, lineWidth: 1.25)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}
