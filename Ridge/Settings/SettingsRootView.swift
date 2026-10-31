import AppKit
import SwiftUI

/// 页面白底；分组卡片用与主题预设相同的浅灰底。
enum SettingsChrome {
    static let pageBackground = Color.white
    /// 与 IslandThemeChip 未选中态一致。
    static let cardBackground = Color.primary.opacity(0.04)
    static let nsPageBackground = NSColor.white
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case island
    case widgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: return "灵动岛"
        case .widgets: return "小组件"
        }
    }

    var systemImage: String {
        switch self {
        case .island: return "rectangle.topthird.inset.filled"
        case .widgets: return "rectangle.3.group"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: IslandSettings
    @ObservedObject private var widgetSettings = WidgetSettings.shared
    @ObservedObject private var navigator = SettingsNavigator.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $navigator.section) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch navigator.section {
                case .island:
                    IslandSettingsPane(settings: settings)
                case .widgets:
                    WidgetsSettingsPane(settings: widgetSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsChrome.pageBackground)
        }
        .navigationTitle(navigator.section.title)
        .preferredColorScheme(.light)
        .background(SettingsChrome.pageBackground)
        .frame(minWidth: 860, minHeight: 560)
    }
}
