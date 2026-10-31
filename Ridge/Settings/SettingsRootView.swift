import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case general
    case island
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .general: return "通用"
        case .island: return "灵动岛"
        case .privacy: return "隐私"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .general: return "gearshape"
        case .island: return "rectangle.topthird.inset.filled"
        case .privacy: return "hand.raised"
        }
    }

    var group: SettingsSidebarGroup {
        switch self {
        case .overview: return .overview
        case .general, .island, .privacy: return .settings
        }
    }
}

enum SettingsSidebarGroup: String, CaseIterable {
    case overview
    case settings

    var title: String {
        switch self {
        case .overview: return "总览"
        case .settings: return "设置"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: IslandSettings
    @State private var selection: SettingsSection = .island

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsSidebarGroup.allCases, id: \.rawValue) { group in
                    Section(group.title) {
                        ForEach(SettingsSection.allCases.filter { $0.group == group }) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .overview:
                    PlaceholderSettingsPane(message: "活动与小组件总览将在后续版本提供。")
                case .general:
                    GeneralSettingsPane(settings: settings)
                case .island:
                    IslandSettingsPane(settings: settings)
                case .privacy:
                    PlaceholderSettingsPane(message: "Ridge 默认本机运行。后续权限说明会放在这里。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .navigationTitle(selection.title)
        .preferredColorScheme(.light)
        .background(Color.white)
        .frame(minWidth: 860, minHeight: 560)
    }
}

private struct PlaceholderSettingsPane: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settings: IslandSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard {
                    Toggle("启动后显示菜单栏图标", isOn: .constant(true))
                        .disabled(true)
                    Text("菜单栏入口用于打开本设置窗与退出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .background(Color.white)
    }
}
