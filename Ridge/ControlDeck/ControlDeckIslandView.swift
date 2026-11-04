import SwiftUI

/// 控制台内容画布：宽高由本模块给出，岛壳只加 IslandChrome 后测量。
enum ControlDeckContentSize {
    /// 内容区宽度（不含左右 IslandChrome）。
    static let width: CGFloat = NotchGeometry.controlDeckPreferredWidth - IslandChrome.horizontalInsetTotal

    /// 混音台 / 货架 / 项目等内容高度（不含顶 chrome 与底 padding）。
    static func height(
        pane: ControlDeckSettings.Pane?,
        batteryDeviceCount: Int,
        notchHeight: CGFloat
    ) -> CGFloat {
        let topChrome = IslandChrome.expandedTopInset(notchHeight: notchHeight)
        let chromeTotal = topChrome + IslandChrome.contentBottom
        let panelHeight: CGFloat = {
            switch pane {
            case .battery:
                return batteryDeviceCount > NotchGeometry.batteryDeckColumns
                    ? NotchGeometry.controlDeckBatteryDualRowMinHeight
                    : NotchGeometry.controlDeckBatterySingleRowMinHeight
            case .shelf, .volume, .projects, nil:
                return NotchGeometry.controlDeckMinHeight
            }
        }()
        return max(120, panelHeight - chromeTotal)
    }
}

/// 岛上控制台页：当前页只展示对应已开启模块（每模块一页，左右滑动切换）。
struct ControlDeckIslandView: View {
    @ObservedObject private var settings = ControlDeckSettings.shared
    @ObservedObject private var runtime = WidgetRuntime.shared
    @ObservedObject private var batterySession = BatterySession.shared
    @Environment(\.islandNotchHeight) private var notchHeight

    private var canvasSize: CGSize {
        CGSize(
            width: ControlDeckContentSize.width,
            height: ControlDeckContentSize.height(
                pane: currentPane,
                batteryDeviceCount: batterySession.devices.count,
                notchHeight: notchHeight
            )
        )
    }

    var body: some View {
        Group {
            switch currentPane {
            case .shelf:
                ShelfClipboardDeckView()
            case .volume:
                SoundMixerDeckView()
            case .projects:
                ProjectReleaseDeckView()
            case .battery:
                BatteryDeckView()
            case .none:
                Color.clear
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .accessibilityLabel(currentPane?.title ?? L10n.ControlDeck.title)
        .onAppear {
            reconcilePane()
            AppLog.debug("ControlDeck", "控制台画布尺寸", [
                "w": canvasSize.width,
                "h": canvasSize.height,
                "pane": currentPane?.rawValue ?? "nil",
                "devices": batterySession.devices.count
            ])
        }
        .onChange(of: runtime.activeID) { _, _ in
            reconcilePane()
        }
    }

    private var currentPane: ControlDeckSettings.Pane? {
        if let id = runtime.activeID,
           let pane = ControlDeckSettings.Pane.from(pageID: id),
           settings.enabledPanes.contains(pane) {
            return pane
        }
        if settings.enabledPanes.contains(settings.activePane) {
            return settings.activePane
        }
        return settings.enabledPanes.first
    }

    private func reconcilePane() {
        guard let id = runtime.activeID else { return }
        settings.syncActivePane(fromPageID: id)
    }
}
