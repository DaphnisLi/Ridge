import SwiftUI

/// 左右翼 flush 胶囊（双槽一侧 / 待命小岛）的尺寸与三态色，对照设计稿。
/// 真岛双槽标准以音乐左翼为准：壳层黑底 + bare 内容三区（外 | 中 | 刘海侧），禁止再套黑胶囊。
enum IslandFlushWingStyle {
    /// 单侧胶囊约宽（稿 ~106–114）；仅设置样张/独立预览用。
    static let width: CGFloat = 112
    static let height: CGFloat = 34
    static let horizontalPadding: CGFloat = 10
    /// 真岛 dual bare：内容左右内边距（对齐 `MediaCompactStandbyView.wingLeadContent`）。
    static let bareContentLeading: CGFloat = 10
    static let bareContentTrailing: CGFloat = 8
    /// 三区 Spacer 最小间隙（图标 | 主文案 | 右侧指示）。
    static let bareContentSpacerMin: CGFloat = 6
    /// 贴顶直角；外侧下角圆（右翼 outer=右下，左翼 outer=左下）。
    static let outerBottomRadius: CGFloat = 14

    /// 正常 / 信息强调描边与图标（稿 `#adc6ff`；黑底上用，**禁止**当实心胶囊 fill）。
    static let accentInfo = Color(red: 0.678, green: 0.776, blue: 1.0)
    /// 「已连接」等实心/描边胶囊用的饱和蓝（旧 tip `accentBlue`）；勿用浅 `accentInfo` 当 fill。
    static let accentInfoSolid = Color(red: 0.20, green: 0.48, blue: 0.96)
    /// 成功 / 播放（稿 `#72fe88` / secondary-fixed）。
    static let accentSuccess = Color(red: 0.447, green: 0.996, blue: 0.522)
    /// 警告（稿久坐 `#ff9f0a`）。
    static let accentWarning = Color(red: 1.0, green: 0.624, blue: 0.039)
    /// 危险（系统红 `#FF3B30`）。
    static let accentDanger = Color(red: 1.0, green: 0.231, blue: 0.188)
    /// 入会 morph 底（稿 primary-container `#0070eb`）。
    static let joinFill = Color(red: 0.0, green: 0.439, blue: 0.922)

    enum Severity: Equatable {
        case info
        case success
        case warning
        case danger

        var accent: Color {
            switch self {
            case .info: return IslandFlushWingStyle.accentInfo
            case .success: return IslandFlushWingStyle.accentSuccess
            case .warning: return IslandFlushWingStyle.accentWarning
            case .danger: return IslandFlushWingStyle.accentDanger
            }
        }
    }

    /// 右翼：仅右下圆；左翼：仅左下圆。上沿直角贴刘海。
    static func capsuleShape(side: Side) -> UnevenRoundedRectangle {
        switch side {
        case .leading:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: outerBottomRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .trailing:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: outerBottomRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        }
    }

    enum Side {
        case leading
        case trailing
    }
}

/// 双槽一侧用的 flush 胶囊壳：黑底 + 贴顶直角 + 外侧下圆。
/// 仅设置样张/独立预览用；真岛双槽左右翼不要再套黑壳（岛壳已是黑，再套会叠成下方一条）。
struct IslandFlushWingCapsule<Content: View>: View {
    var side: IslandFlushWingStyle.Side = .trailing
    var width: CGFloat = IslandFlushWingStyle.width
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, IslandFlushWingStyle.horizontalPadding)
            .frame(width: width, height: IslandFlushWingStyle.height)
            .background(
                IslandFlushWingStyle.capsuleShape(side: side)
                    .fill(Color.black)
            )
            .clipShape(IslandFlushWingStyle.capsuleShape(side: side))
    }
}

/// 真岛双槽 bare 内容：铺满翼槽，左右内边距对齐音乐标准。
extension View {
    func islandBareFlushWingContent() -> some View {
        padding(.leading, IslandFlushWingStyle.bareContentLeading)
            .padding(.trailing, IslandFlushWingStyle.bareContentTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// 双槽贴刘海：左翼 | 刘海空隙 | 右翼；高=刘海。左右不必等宽。
/// **禁止**用 GeometryReader：IslandBody 包了 `.fixedSize`，GeoReader 理想宽≈0 → 只剩黑底空条。
struct IslandDualNotchWingRow<Left: View, Right: View>: View {
    var previewNotchWidth: CGFloat = 110
    /// 右侧是「已复制」Ø32：右槽仅圆岛宽，勿再留对称黑翼。
    var rightIsOrb: Bool = false
    /// 左右 flush 翼内容宽；进程结束 tip 可传紧凑宽。
    var wingWidth: CGFloat = IslandChrome.dualFlushLeftWingWidth
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var notchWidth: CGFloat {
        envNotchWidth > 40 ? envNotchWidth : previewNotchWidth
    }

    private var panelSize: CGSize {
        IslandChrome.preparedDualFlushPanelSize(
            notchWidth: notchWidth,
            notchHeight: envNotchHeight > 1 ? envNotchHeight : IslandFlushWingStyle.height,
            rightIsOrb: rightIsOrb,
            wingWidth: wingWidth
        )
    }

    var body: some View {
        let total = panelSize.width
        let height = panelSize.height
        let notch = min(max(notchWidth, 1), total * 0.72)
        // 左翼黑底伸进刘海 underlap；右「已复制」保持原 Ø32 圆岛，禁止 clip/长方形黑底改形。
        let leftUnderlap = rightIsOrb
            ? min(IslandChrome.dualFlushNotchUnderlap, max(0, notch - 8))
            : min(IslandChrome.dualFlushNotchUnderlap, max(0, (notch - 4) / 2))
        let rightUnderlap: CGFloat = rightIsOrb ? 0 : leftUnderlap
        // 左右 flush 翼同宽；仅「已复制」右槽收成 Ø32。
        let leftContentW = wingWidth
        let rightW: CGFloat = rightIsOrb
            ? IslandChrome.notchRightOrbDiameter
            : wingWidth
        // 与单独「已复制」一致：圆岛贴刘海外缘 + notchRightOrbGap，勿再 nudge/clip。
        let gap: CGFloat = rightIsOrb ? IslandChrome.notchRightOrbGap : 0
        return HStack(spacing: 0) {
            left()
                .frame(width: leftContentW, height: height, alignment: .center)
                .clipped()
            Color.clear
                .frame(width: leftUnderlap, height: height)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: max(0, notch - leftUnderlap - rightUnderlap), height: height)
                .accessibilityHidden(true)
            if rightUnderlap > 0 {
                Color.clear
                    .frame(width: rightUnderlap, height: height)
                    .accessibilityHidden(true)
            }
            if gap > 0 {
                Color.clear
                    .frame(width: gap, height: height)
                    .accessibilityHidden(true)
            }
            Group {
                if rightIsOrb {
                    // 圆岛禁止 .clipped()：外框 clip 曾把 Ø32 切成异形黑块。
                    right()
                        .frame(width: rightW, height: height, alignment: .center)
                } else {
                    right()
                        .frame(width: rightW, height: height, alignment: .center)
                        .clipped()
                }
            }
        }
        .frame(width: total, height: height)
        .onAppear {
            AppLog.warn("Island", "双槽贴刘海内容已布局", [
                "panelW": Int(total),
                "panelH": Int(height),
                "notch": Int(notch),
                "leftContent": Int(leftContentW),
                "leftUnderlap": Int(leftUnderlap),
                "rightW": Int(rightW),
                "orb": rightIsOrb
            ])
        }
    }
}
