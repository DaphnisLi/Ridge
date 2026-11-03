import SwiftUI

/// 岛上控制台页：当前页只展示对应已开启模块（每模块一页，左右滑动切换）。
struct ControlDeckIslandView: View {
    @ObservedObject private var settings = ControlDeckSettings.shared
    @ObservedObject private var runtime = WidgetRuntime.shared

    var body: some View {
        Group {
            switch currentPane {
            case .shelf:
                ShelfClipboardDeckView()
            case .volume:
                SoundMixerDeckView()
            case .projects:
                ProjectReleaseDeckView()
            case .battery:
                BatteryDeckView()
            case .none:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(currentPane?.title ?? L10n.ControlDeck.title)
        .onAppear {
            reconcilePane()
        }
        .onChange(of: runtime.activeID) { _, _ in
            reconcilePane()
        }
    }

    private var currentPane: ControlDeckSettings.Pane? {
        if let id = runtime.activeID,
           let pane = ControlDeckSettings.Pane.from(pageID: id),
           settings.enabledPanes.contains(pane) {
            return pane
        }
        if settings.enabledPanes.contains(settings.activePane) {
            return settings.activePane
        }
        return settings.enabledPanes.first
    }

    private func reconcilePane() {
        guard let id = runtime.activeID else { return }
        settings.syncActivePane(fromPageID: id)
    }
}
