import Combine
import Foundation
import SwiftUI

/// 世界时钟：固钉城市在岛上展开多列；设置中搜索添加与呈现偏好。
@MainActor
final class WorldClockWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.worldClock",
        displayName: L10n.WorldClock.widgetName,
        summary: L10n.WorldClock.widgetSummary,
        source: .builtin,
        kind: .content,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let session = WorldClockSession.shared
    private let widgetSettings = WidgetSettings.shared

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    var title: String { "" }

    private var observers: Set<AnyCancellable> = []

    init(context: WidgetContext) {
        self.context = context
        widgetSettings.$disabledIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncEnabled(reason: "settings")
            }
            .store(in: &observers)
        session.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncDemand(reason: "session")
            }
            .store(in: &observers)
        syncEnabled(reason: "init")
    }

    func makeView() -> AnyView {
        AnyView(
            WorldClockIslandView(
                session: session,
                settings: WorldClockSettings.shared
            )
        )
    }

    func onAppear() {
        context.log("世界时钟 onAppear")
        syncEnabled(reason: "appear")
    }

    func onDisappear() {
        context.log("世界时钟 onDisappear")
    }

    func refresh() {
        syncEnabled(reason: "refresh")
    }

    private func syncEnabled(reason: String) {
        let enabled = widgetSettings.isEnabled(Self.manifest.id)
        session.setWidgetEnabled(enabled)
        syncDemand(reason: reason)
    }

    private func syncDemand(reason: String) {
        let shouldShow = session.wantsIslandDisplay
        if shouldShow {
            if !wantsDisplay {
                wantsDisplay = true
                requestedAt = Date()
                AppLog.warn("WorldClock", "申请展示", [
                    "reason": reason,
                    "cities": session.snapshots.count
                ])
                Task { @MainActor [weak self] in
                    self?.context.requestDisplay()
                }
            }
        } else if wantsDisplay {
            wantsDisplay = false
            AppLog.warn("WorldClock", "撤回展示", ["reason": reason])
            context.withdrawDisplay()
        }
    }
}
