import Foundation
import SwiftUI

/// 网络 / VPN tip：主路径切换与 VPN 通断走 `system.islandNotice`；不做常驻网速页。
@MainActor
final class NetworkLinkTipWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.networkLinkTip",
        displayName: L10n.NetworkLink.widgetName,
        summary: L10n.NetworkLink.widgetSummary,
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
        NetworkLinkSession.shared.start()
        context.log("网络 tip 小组件已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("网络 tip onAppear（不应上岛常驻）")
        NetworkLinkSession.shared.start()
    }

    func onDisappear() {
        context.log("网络 tip onDisappear")
    }

    func refresh() {
        NetworkLinkSession.shared.refresh(reason: "networkLinkTipRefresh")
    }
}
