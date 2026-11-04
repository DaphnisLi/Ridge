import Combine
import Foundation
import SwiftUI

/// 番茄倒计时：开启后常驻选时态；计时中收起为待命、悬停展开进行中 / 顺延 / 终局。
@MainActor
final class FocusTimerWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.focusTimer",
        displayName: L10n.FocusTimer.widgetName,
        summary: L10n.FocusTimer.widgetSummary,
        source: .builtin,
        kind: .content,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let session = FocusTimerSession.shared
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
            FocusTimerLiveView(
                session: session,
                settings: FocusTimerSettings.shared
            )
        )
    }

    func onAppear() {
        context.log("番茄倒计时 onAppear")
        syncEnabled(reason: "appear")
    }

    func onDisappear() {
        context.log("番茄倒计时 onDisappear")
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
                AppLog.info("FocusTimer", "申请展示", ["reason": reason, "phase": session.phase.rawValue])
                Task { @MainActor [weak self] in
                    guard let self, self.wantsDisplay else { return }
                    self.context.requestDisplay()
                }
            }
        } else if wantsDisplay {
            wantsDisplay = false
            context.withdrawDisplay()
            AppLog.info("FocusTimer", "撤回展示", ["reason": reason])
        }
    }
}

private struct FocusTimerLiveView: View {
    @ObservedObject var session: FocusTimerSession
    @ObservedObject var settings: FocusTimerSettings

    var body: some View {
        // 展开区：选时 / 进行中 / 顺延 / 终局。收起待命由 IslandBody 单独渲染。
        FocusTimerIslandCardView(
            snapshot: session.snapshot,
            isExpanded: true,
            onSelectPreset: { session.selectPreset($0) },
            onCustomMinutes: { session.setCustomMinutes($0) },
            onStart: { session.startCustomTimer() },
            onExtend: { session.extend() },
            onFinishEarly: { session.finishEarly() },
            // 仅在「完成命名」时经 onNoteChange 写入；逐字回写会整卡刷新打断 field editor。
            onNoteChange: { session.noteDraft = $0 },
            onSave: { session.saveCompletion(note: nil) },
            presets: settings.presets,
            extendStepMinutes: settings.extendStepMinutes
        )
    }
}
