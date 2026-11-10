import SwiftUI

/// 控制台内容画布：宽高由本模块给出，岛壳只加 IslandChrome 后测量。
enum ControlDeckContentSize {
    /// 内容区宽度（不含左右 IslandChrome）。
    static let width: CGFloat = NotchGeometry.controlDeckPreferredWidth - IslandChrome.horizontalInsetTotal

    /// 混音台 / 货架 / 项目等内容高度（不含顶 chrome 与底 padding）。
    static func height(
        pane: ControlDeckSettings.Pane?,
        batteryDeviceCount: Int,
        volumeDeviceCount: Int = 0,
        volumeAppCount: Int = 0,
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
            case .volume:
                return volumePanelHeight(
                    deviceCount: volumeDeviceCount,
                    appCount: volumeAppCount
                )
            case .shelf, .projects, nil:
                return NotchGeometry.controlDeckMinHeight
            }
        }()
        return max(120, panelHeight - chromeTotal)
    }

    /// 混音台面板高：按左右栏内容估算，上限为原固定高 `controlDeckMinHeight`。
    static func volumePanelHeight(deviceCount: Int, appCount: Int) -> CGFloat {
        let maxPanel = NotchGeometry.controlDeckMinHeight
        let left = estimatedVolumeLeftHeight(deviceCount: deviceCount)
        let right = estimatedVolumeRightHeight(appCount: appCount)
        let needed = max(left, right)
        // 过矮时仍保留一截可读高度。
        let floored = max(needed, 148)
        return min(maxPanel, floored)
    }

    /// 对齐 `SoundMixerDeckView` 左栏：主音量 + 整表设备（选中卡更高）。
    private static func estimatedVolumeLeftHeight(deviceCount: Int) -> CGFloat {
        let padding: CGFloat = 24
        let masterBlock: CGFloat = 34
        let sectionHeader: CGFloat = 32
        guard deviceCount > 0 else {
            return padding + masterBlock + sectionHeader + 22
        }
        // 选中卡约 48，未选中行约 34；列表内共滚。
        let list = 48 + CGFloat(max(0, deviceCount - 1)) * 34
        return padding + masterBlock + sectionHeader + list
    }

    /// 对齐右栏：标题 + App 行（最多展示 8）。
    private static func estimatedVolumeRightHeight(appCount: Int) -> CGFloat {
        let padding: CGFloat = 24
        let header: CGFloat = 36
        let shown = min(max(appCount, 0), 8)
        if shown == 0 {
            return padding + header + 36
        }
        let listTop: CGFloat = 10
        let row: CGFloat = 38
        return padding + header + listTop + CGFloat(shown) * row
    }
}

/// 岛上控制台页：当前页只展示对应已开启模块（每模块一页，左右滑动切换）。
struct ControlDeckIslandView: View {
    @ObservedObject private var settings = ControlDeckSettings.shared
    @ObservedObject private var runtime = WidgetRuntime.shared
    @ObservedObject private var batterySession = BatterySession.shared
    @ObservedObject private var soundSession = SoundSession.shared
    @Environment(\.islandNotchHeight) private var notchHeight

    private var volumeDeviceCount: Int {
        SoundMixerDebugMock.enabled
            ? SoundMixerDebugMock.devices.count
            : soundSession.outputDevices.count
    }

    private var volumeAppCount: Int {
        SoundMixerDebugMock.enabled
            ? SoundMixerDebugMock.apps.count
            : soundSession.apps.count
    }

    private var canvasSize: CGSize {
        CGSize(
            width: ControlDeckContentSize.width,
            height: ControlDeckContentSize.height(
                pane: currentPane,
                batteryDeviceCount: batterySession.devices.count,
                volumeDeviceCount: volumeDeviceCount,
                volumeAppCount: volumeAppCount,
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
            logCanvasSize(reason: "appear")
        }
        .onChange(of: runtime.activeID) { _, _ in
            reconcilePane()
        }
        .onChange(of: volumeDeviceCount) { _, _ in
            guard currentPane == .volume else { return }
            logCanvasSize(reason: "volumeDevices")
        }
        .onChange(of: volumeAppCount) { _, _ in
            guard currentPane == .volume else { return }
            logCanvasSize(reason: "volumeApps")
        }
    }

    private func logCanvasSize(reason: String) {
        AppLog.warn("ControlDeck", "控制台画布尺寸", [
            "reason": reason,
            "w": Int(canvasSize.width),
            "h": Int(canvasSize.height),
            "pane": currentPane?.rawValue ?? "nil",
            "battery": batterySession.devices.count,
            "volDev": volumeDeviceCount,
            "volApp": volumeAppCount,
            "mock": SoundMixerDebugMock.enabled
        ])
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
