import Combine
import Foundation
import SwiftUI

/// 久坐起身：设置中配置；岛上**不常驻**，触阈由 `MoveReminderSession` → `IslandNoticeCenter` 投递。
@MainActor
final class MoveReminderWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.moveReminder",
        displayName: L10n.MoveReminder.widgetName,
        summary: L10n.MoveReminder.widgetSummary,
        source: .builtin,
        kind: .content,
        supportsPinning: false,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let session = MoveReminderSession.shared
    private let settings = MoveReminderSettings.shared

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
                self?.context.log("久坐提醒设置变更")
            }
            .store(in: &observers)
        context.log("久坐提醒小组件已创建（瞬时通知模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("久坐提醒 onAppear（不应上岛常驻）")
        session.start()
    }

    func onDisappear() {
        context.log("久坐提醒 onDisappear")
    }

    func refresh() {
        session.start()
    }
}
