import Foundation
import SwiftUI

/// 隔空投送文件接收完成 tip（产品 **D**）：落盘后瞬时提示，点按打开文件。
@MainActor
final class AirDropReceiveTipWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.airDropReceive",
        displayName: L10n.AirDropReceive.widgetName,
        summary: L10n.AirDropReceive.widgetSummary,
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
        AirDropReceiveSession.shared.start()
        context.log("隔空投送接收 tip 已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("隔空投送 tip onAppear（不应上岛常驻）")
        AirDropReceiveSession.shared.start()
    }

    func onDisappear() {
        context.log("隔空投送 tip onDisappear")
    }

    func refresh() {
        // 目录监视自驱。
    }
}
