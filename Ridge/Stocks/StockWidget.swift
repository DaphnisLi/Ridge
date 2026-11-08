import Combine
import Foundation
import SwiftUI

/// 股票行情：固钉最多三席，岛上并排展示现价 / 涨跌 / 分时。
@MainActor
final class StockWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.stocks",
        displayName: L10n.Stocks.widgetName,
        summary: L10n.Stocks.widgetSummary,
        source: .builtin,
        kind: .content,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let session = StockSession.shared
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
            StockIslandView(
                session: session,
                settings: StockSettings.shared
            )
        )
    }

    func onAppear() {
        context.log("股票 onAppear")
        syncEnabled(reason: "appear")
    }

    func onDisappear() {
        context.log("股票 onDisappear")
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
                AppLog.warn("Stocks", "申请展示", [
                    "reason": reason,
                    "pins": StockSettings.shared.pins.count
                ])
                Task { @MainActor [weak self] in
                    self?.context.requestDisplay()
                }
            }
        } else if wantsDisplay {
            wantsDisplay = false
            AppLog.warn("Stocks", "撤回展示", ["reason": reason])
            context.withdrawDisplay()
        }
    }
}
