import Combine
import Foundation
import SwiftUI

/// 外设提示：低电 / 满电 / 接入合并为一张库卡；岛上永不常驻，走 `system.islandNotice`。
@MainActor
final class PeripheralTipWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.peripheralTip",
        displayName: L10n.PeripheralTip.widgetName,
        summary: L10n.PeripheralTip.widgetSummary,
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
        BatterySession.shared.start()
        context.log("外设提示小组件已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("外设提示 onAppear（不应上岛常驻）")
        BatterySession.shared.start()
    }

    func onDisappear() {
        context.log("外设提示 onDisappear")
    }

    func refresh() {
        BatterySession.shared.refresh(reason: "peripheralTipRefresh")
    }
}
