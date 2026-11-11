import Foundation
import SwiftUI

/// 「已复制」瞬时提示：库内独立开关；岛上永不常驻。
@MainActor
final class CopiedNoticeWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.copiedNotice",
        displayName: L10n.CopiedNotice.widgetName,
        summary: L10n.CopiedNotice.widgetSummary,
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
        ShelfSettings.shared.migrateCopiedNoticeWidgetGateIfNeeded()
        context.log("已复制提示小组件已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("已复制提示 onAppear（不应上岛常驻）")
    }

    func onDisappear() {
        context.log("已复制提示 onDisappear")
    }

    func refresh() {}
}
