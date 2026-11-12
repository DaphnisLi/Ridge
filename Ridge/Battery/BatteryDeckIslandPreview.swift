import SwiftUI

/// 设置页电量预览：布局与真岛控制台电量页同构（画布尺寸 + 圆角 + 同款卡片）。
/// 底色用主题 `palette.fill`（经典黑为 sRGB 纯黑）。
/// 禁止在设置窗里用 `IslandOpaqueFillView`+device 黑——不透明窗上会被抬成炭灰。
/// 禁止画分页角点：设置样张不是多页控制台，左右上角不应出现点儿。
/// 库卡同比缩放到 `SettingsIslandPreviewWidth.library` 由 `WidgetSamplePreview.island` 统一处理。
struct BatteryDeckIslandPreview: View {
    @ObservedObject private var settings = IslandSettings.shared
    var devices: [BatteryDevice] = BatteryDeckView.sampleDevices
    /// 预览用典型刘海高；顶距只保留「刘海下沿→内容」可见间隙（无硬件遮挡）。
    var notchHeight: CGFloat = 32

    private var canvasWidth: CGFloat {
        ControlDeckContentSize.batteryContentWidth(deviceCount: devices.count)
    }

    private var canvasHeight: CGFloat {
        ControlDeckContentSize.batteryContentCanvasHeight(deviceCount: devices.count)
    }

    /// 可见顶距：勿照搬含刘海盲区的 `expandedTopInset`，否则大块空黑会让卡片/文字显得发闷。
    private var visibleTopInset: CGFloat {
        IslandChrome.previewExpandedVisibleTopInset(notchHeight: notchHeight)
    }

    /// 与 `IslandContentView.appliedBottomRadius` 控制台分支一致：至少 26。
    private var bottomRadius: CGFloat {
        let preferred = max(CGFloat(settings.bottomCornerRadius), 26)
        let panelH = canvasHeight + visibleTopInset + IslandChrome.contentBottom
        let panelW = canvasWidth + IslandChrome.horizontalInsetTotal
        return min(preferred, panelH / 2, panelW / 2)
    }

    /// 未缩放时黑岛固有尺寸（含 chrome）；库卡缩放系数见 `libraryPreviewScale`。
    static func nativePanelSize(
        deviceCount: Int = BatteryDeckView.sampleDevices.count,
        notchHeight: CGFloat = 32
    ) -> CGSize {
        let canvasW = ControlDeckContentSize.batteryContentWidth(deviceCount: deviceCount)
        let canvasH = ControlDeckContentSize.batteryContentCanvasHeight(deviceCount: deviceCount)
        let top = IslandChrome.previewExpandedVisibleTopInset(notchHeight: notchHeight)
        return CGSize(
            width: canvasW + IslandChrome.horizontalInsetTotal,
            height: canvasH + top + IslandChrome.contentBottom
        )
    }

    /// 库卡灰舞台内：黑岛缩到 `SettingsIslandPreviewWidth.library`（与统一 modifier 同公式）。
    static var libraryPreviewScale: CGFloat {
        SettingsIslandPreviewWidth.libraryScale(nativeWidth: nativePanelSize().width)
    }

    var body: some View {
        let shape = IslandOutlineShape(style: .panel, bottomRadius: bottomRadius)
        let top = visibleTopInset
        let panelW = canvasWidth + IslandChrome.horizontalInsetTotal
        let panelH = canvasHeight + top + IslandChrome.contentBottom
        let palette = settings.theme.palette

        return ZStack(alignment: .top) {
            shape.fill(palette.fill)

            BatteryDeckView(previewDevices: devices)
                .frame(width: canvasWidth, height: canvasHeight)
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.top, top)
                .padding(.bottom, IslandChrome.contentBottom)
                .environment(\.islandPalette, palette)
                .environment(\.islandNotchHeight, notchHeight)
        }
        .frame(width: panelW, height: panelH)
        .clipShape(shape)
        .overlay(
            shape.stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        // 真岛 hosting 强制 darkAqua；设置窗浅色下若不锁深色，白字/卡片灰底会漂。
        .preferredColorScheme(.dark)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.ControlDeck.moduleBattery)
        .onAppear {
            AppLog.debug("Battery", "电量岛预览已显示", [
                "devices": devices.count,
                "w": Int(panelW),
                "h": Int(panelH),
                "theme": settings.theme.rawValue,
                "topInset": Int(top)
            ])
        }
    }
}
