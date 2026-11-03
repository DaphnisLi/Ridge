import AppKit
import SwiftUI

/// 设置 UI 色板（对齐会议设置 HTML mock）。
enum SettingsChrome {
    /// 设置窗默认 / 最小内容尺寸（菜单栏与 App「设置…」共用，禁止另开一套）。
    static let windowDefaultSize = NSSize(width: 1200, height: 620)
    static let windowMinSize = NSSize(width: 1080, height: 520)

    /// 页面底 surface `#fbfbfd`
    static let pageBackground = Color(red: 0.984, green: 0.984, blue: 0.992)
    /// 卡片底 surface-container-lowest `#ffffff`
    static let cardBackground = Color.white
    /// surface-container-low `#f5f5f7`
    static let surfaceContainerLow = Color(red: 0.961, green: 0.961, blue: 0.969)
    /// surface-container `#efeff2`
    static let surfaceContainer = Color(red: 0.937, green: 0.937, blue: 0.949)
    /// on-surface `#1d1d1f`
    static let onSurface = Color(red: 0.114, green: 0.114, blue: 0.122)
    /// on-surface-variant `#6e6e73`
    static let onSurfaceVariant = Color(red: 0.431, green: 0.431, blue: 0.451)
    /// primary `#0071e3`
    static let primary = Color(red: 0.0, green: 0.443, blue: 0.890)
    /// primary-container `#0077ed`
    static let primaryContainer = Color(red: 0.0, green: 0.467, blue: 0.929)
    /// secondary / success `#34c759`
    static let secondary = Color(red: 0.204, green: 0.780, blue: 0.349)
    /// error `#ff3b30`
    static let error = Color(red: 1.0, green: 0.231, blue: 0.188)
    /// outline `#d2d2d7`
    static let outline = Color(red: 0.824, green: 0.824, blue: 0.843)
    /// outline-variant `#e5e5ea`
    static let outlineVariant = Color(red: 0.898, green: 0.898, blue: 0.918)
    /// 卡片描边：细线 + 低对比，避免厚重。
    static let cardStroke = outlineVariant.opacity(0.55)
    static let cardStrokeWidth: CGFloat = 1
    /// 输入框 placeholder 与 mock 一致的浅灰。
    static let placeholder = onSurfaceVariant.opacity(0.55)

    static let nsPageBackground = NSColor(calibratedRed: 0.984, green: 0.984, blue: 0.992, alpha: 1)
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case island
    case widgets
    case resourceMonitor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: return L10n.Settings.island
        case .widgets: return L10n.Settings.widgets
        case .resourceMonitor: return L10n.Settings.resourceMonitor
        }
    }

    var systemImage: String {
        switch self {
        case .island: return "rectangle.topthird.inset.filled"
        case .widgets: return "rectangle.3.group"
        case .resourceMonitor: return "chart.bar.xaxis"
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
                case .resourceMonitor:
                    ResourceMonitorSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsChrome.pageBackground)
        }
        .navigationTitle(navigator.section.title)
        .preferredColorScheme(.light)
        .background(SettingsChrome.pageBackground)
        .frame(
            minWidth: SettingsChrome.windowMinSize.width,
            minHeight: SettingsChrome.windowMinSize.height
        )
        .frame(
            idealWidth: SettingsChrome.windowDefaultSize.width,
            idealHeight: SettingsChrome.windowDefaultSize.height
        )
    }
}
