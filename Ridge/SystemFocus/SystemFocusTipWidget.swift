import Foundation
import SwiftUI

/// 系统 Focus / 勿扰 tip：开·关·切换走 `system.islandNotice`；与 Ridge「专注计时」无关。
@MainActor
final class SystemFocusTipWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.systemFocusTip",
        displayName: L10n.SystemFocus.widgetName,
        summary: L10n.SystemFocus.widgetSummary,
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
        SystemFocusSession.shared.start()
        context.log("系统 Focus tip 小组件已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("系统 Focus tip onAppear（不应上岛常驻）")
        SystemFocusSession.shared.start()
    }

    func onDisappear() {
        context.log("系统 Focus tip onDisappear")
    }

    func refresh() {
        SystemFocusSession.shared.refresh(reason: "systemFocusTipRefresh")
    }
}
