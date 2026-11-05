import Combine
import Foundation
import SwiftUI

/// AI 额度：仅在设置中配置；岛上**永不常驻**。
/// 触达充裕 / 警戒 / 截流任一阈值时由 `AIUsageSession` → `IslandNoticeCenter` 投递约 3s 瞬时提示。
@MainActor
final class AIUsageWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.aiUsage",
        displayName: L10n.AIUsage.widgetName,
        summary: L10n.AIUsage.widgetSummary,
        source: .builtin,
        kind: .content,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let session = AIUsageSession.shared
    private let settings = AIUsageSettings.shared

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    var title: String { "" }

    private var observers: Set<AnyCancellable> = []

    init(context: WidgetContext) {
        self.context = context
        session.start()
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.context.log("AI 额度设置变更（仅后台感知，不上岛常驻）")
            }
            .store(in: &observers)
        context.log("AI 额度小组件已创建（瞬时通知模式）")
    }

    /// 不提供常驻页；真提示走 `system.islandNotice`。
    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("AI 额度 onAppear（不应上岛；若见到说明调度异常）")
        session.start()
    }

    func onDisappear() {
        context.log("AI 额度 onDisappear")
    }

    func refresh() {
        Task { await session.refresh(reason: "widgetRefresh") }
    }
}
