import AppKit
import SwiftUI

/// 设置 UI 设计令牌：色板 / 字号 / 间距 / 圆角。设置页一律引用此处，禁止页内散落魔法数。
enum SettingsChrome {
    /// 设置窗默认 / 最小内容尺寸（菜单栏与 App「设置…」共用，禁止另开一套）。
    static let windowDefaultSize = NSSize(width: 1200, height: 620)
    static let windowMinSize = NSSize(width: 1080, height: 520)
    /// 侧栏贴底「设置」区高度（分区标题 + 通用 / 关于两行）。
    static let sidebarPinnedFooterHeight: CGFloat = 112

    // MARK: Color

    /// 页面底 surface `#fbfbfd`
    static let pageBackground = Color(red: 0.984, green: 0.984, blue: 0.992)
    /// 卡片底 `#ffffff`——所有设置小卡片统一白底。
    static let cardBackground = Color.white
    /// surface-container-low `#f5f5f7`（嵌套浅底、chip，不作主卡底）
    static let surfaceContainerLow = Color(red: 0.961, green: 0.961, blue: 0.969)
    /// surface-container `#efeff2`
    static let surfaceContainer = Color(red: 0.937, green: 0.937, blue: 0.949)
    /// surface-container-highest（进程树 / 专注排行嵌套底）
    static let surfaceContainerHighest = Color(red: 0.894, green: 0.886, blue: 0.894)
    /// on-surface `#1d1d1f`
    static let onSurface = Color(red: 0.114, green: 0.114, blue: 0.122)
    /// on-surface-variant `#6e6e73`
    static let onSurfaceVariant = Color(red: 0.431, green: 0.431, blue: 0.451)
    /// primary `#0071e3`
    static let primary = Color(red: 0.0, green: 0.443, blue: 0.890)
    /// primary-container `#0077ed`
    static let primaryContainer = Color(red: 0.0, green: 0.467, blue: 0.929)
    /// secondary / success `#34c759`（开关成功指示、图钉图标）
    static let secondary = Color(red: 0.204, green: 0.780, blue: 0.349)
    /// secondary-container 浅绿底（夏令时角标等）`#d1f7e2`
    static let secondaryContainer = Color(red: 0.820, green: 0.969, blue: 0.886)
    /// on-secondary-container 深绿字 `#006e28`
    static let onSecondaryContainer = Color(red: 0.0, green: 0.431, blue: 0.157)
    /// error `#ff3b30`
    static let error = Color(red: 1.0, green: 0.231, blue: 0.188)
    /// outline `#d2d2d7`
    static let outline = Color(red: 0.824, green: 0.824, blue: 0.843)
    /// outline-variant `#e5e5ea`
    static let outlineVariant = Color(red: 0.898, green: 0.898, blue: 0.918)
    /// 卡片描边：细线 + 低对比。
    static let cardStroke = outlineVariant.opacity(0.55)
    static let cardStrokeWidth: CGFloat = 1
    /// 输入框 placeholder。
    static let placeholder = onSurfaceVariant.opacity(0.55)

    static let nsPageBackground = NSColor(calibratedRed: 0.984, green: 0.984, blue: 0.992, alpha: 1)

    // MARK: Typography

    enum Font {
        /// 侧栏 / 顶栏分区名旁的详情大标题（少用；一般用系统 navigationTitle）。
        static let pageTitle = SwiftUI.Font.system(size: 18, weight: .bold)
        /// 番茄预设档位大号分钟。
        static let heroMetric = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        /// 概览指标 / 并排预设档位的中号数值（约 22）。
        static let metricEmphasis = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        /// `SettingsPaneSection` 标题。
        static let sectionTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        /// 卡内主标题（项目扫描目录等面板头）。
        static let panelTitle = SwiftUI.Font.system(size: 17, weight: .bold)
        /// 表单行主文案（开关行等）。
        static let rowTitle = SwiftUI.Font.system(size: 13, weight: .regular)
        /// Bento 卡标题 / 滑条标签。
        static let cardTitle = SwiftUI.Font.system(size: 12, weight: .semibold)
        /// 卡内标签（中等字重）。
        static let label = SwiftUI.Font.system(size: 12, weight: .medium)
        /// 正文说明。
        static let body = SwiftUI.Font.system(size: 12, weight: .regular)
        /// 次要说明 / 副标题。
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
        /// 分段条 / chip 未选中。
        static let chip = SwiftUI.Font.system(size: 11, weight: .medium)
        /// 分段条 / chip 选中。
        static let chipSelected = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// 刻度、脚注。
        static let footnote = SwiftUI.Font.system(size: 10, weight: .regular)
        /// 徽章微字。
        static let micro = SwiftUI.Font.system(size: 10, weight: .regular)
        /// 「使用中」等更小徽章。
        static let badgeTiny = SwiftUI.Font.system(size: 9, weight: .medium)
        /// 数值（等宽）。
        static let monoValue = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced)
        /// 小等宽标注。
        static let monoCaption = SwiftUI.Font.system(size: 10, weight: .regular, design: .monospaced)
        /// 强调等宽数值。
        static let monoEmphasis = SwiftUI.Font.system(size: 12, weight: .semibold, design: .monospaced)
        /// 中等等宽标签。
        static let monoLabel = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced)
        /// 卡内小图标。
        static let iconInline = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// 行首瓦片图标。
        static let iconTile = SwiftUI.Font.system(size: 14, weight: .semibold)
    }

    // MARK: Spacing / Radius

    enum Spacing {
        /// 详情页水平边距。
        static let pageHorizontal: CGFloat = 28
        /// 卡片之间。
        static let stack: CGFloat = 14
        /// 卡内边距。
        static let cardPadding: CGFloat = 16
        /// Bento 卡内主间距。
        static let cardInner: CGFloat = 12
    }

    enum Radius {
        static let card: CGFloat = 12
        static let bento: CGFloat = 16
        static let chip: CGFloat = 8
    }
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    /// 功能：上方。
    case island
    case widgets
    case focusInsights
    case resourceMonitor
    /// 设置（含关于）：贴侧栏底。
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: return L10n.Settings.island
        case .widgets: return L10n.Settings.widgets
        case .resourceMonitor: return L10n.Settings.resourceMonitor
        case .focusInsights: return L10n.Settings.focusInsights
        case .general: return L10n.Settings.general
        case .about: return L10n.Settings.about
        }
    }

    var systemImage: String {
        switch self {
        case .island: return "capsule.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .resourceMonitor: return "chart.bar.fill"
        case .focusInsights: return "keyboard"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// 侧栏分区：功能在上；设置（含关于）贴底。
    enum SidebarGroup: String, CaseIterable, Identifiable {
        case features
        case preferences

        var id: String { rawValue }

        var title: String {
            switch self {
            case .features: return L10n.Settings.sidebarFeatures
            case .preferences: return L10n.Settings.sidebarPreferences
            }
        }

        var sections: [SettingsSection] {
            switch self {
            case .features:
                return [.island, .widgets, .focusInsights, .resourceMonitor]
            case .preferences:
                return [.general, .about]
            }
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
                sidebarSection(.features)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 贴侧栏底：固定高度，避免第二份 List 被上层撑没。
                List(selection: $navigator.section) {
                    sidebarSection(.preferences)
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)
                .frame(height: SettingsChrome.sidebarPinnedFooterHeight)
            }
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
                case .focusInsights:
                    ResourceFocusInsightsPane()
                case .general:
                    GeneralSettingsPane()
                case .about:
                    AboutSettingsPane()
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

    @ViewBuilder
    private func sidebarSection(_ group: SettingsSection.SidebarGroup) -> some View {
        Section(group.title) {
            ForEach(group.sections) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
    }
}
