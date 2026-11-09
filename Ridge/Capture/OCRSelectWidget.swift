import Combine
import Foundation
import SwiftUI

/// 框选文字提取：库内开关 + 快捷键唤醒；岛上**不常驻**，引导走 `system.islandNotice`。
@MainActor
final class OCRSelectWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.ocrSelect",
        displayName: L10n.OCRSelect.widgetName,
        summary: L10n.OCRSelect.widgetSummary,
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
        context.log("框选文字提取小组件已创建（快捷键模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("框选文字提取 onAppear（不应上岛常驻）")
    }

    func onDisappear() {
        context.log("框选文字提取 onDisappear")
    }

    func refresh() {
        CaptureHotKeyCoordinator.shared.sync(reason: "ocrSelectRefresh")
    }
}
