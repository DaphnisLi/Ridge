import Combine
import Foundation
import SwiftUI

/// 本机电池提示：充电中 / 低电 / 充满；岛上永不常驻，走 `system.islandNotice`。
/// 与 `builtin.peripheralTip` 分通道；台式无内置电池时会话静默。
@MainActor
final class MacBatteryTipWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.macBatteryTip",
        displayName: L10n.MacBattery.widgetName,
        summary: L10n.MacBattery.widgetSummary,
        source: .builtin,
        kind: .content,
        supportsPinning: false,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    var title: String { "" }

    init(context: WidgetContext) {
        self.context = context
        MacBatterySession.shared.start()
        context.log("本机电池提示小组件已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("本机电池提示 onAppear（不应上岛常驻）")
        MacBatterySession.shared.start()
    }

    func onDisappear() {
        context.log("本机电池提示 onDisappear")
    }

    func refresh() {
        MacBatterySession.shared.refresh(reason: "macBatteryTipRefresh")
    }
}
