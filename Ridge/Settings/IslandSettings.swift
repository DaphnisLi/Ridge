import Combine
import CoreGraphics
import Foundation

enum IslandDisplayStyle: String, CaseIterable, Identifiable {
    case notch
    case pillBelowMenuBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return L10n.Settings.styleNotch
        case .pillBelowMenuBar: return L10n.Settings.stylePill
        }
    }

    var subtitle: String {
        switch self {
        case .notch: return L10n.Settings.styleNotchSubtitle
        case .pillBelowMenuBar: return L10n.Settings.stylePillSubtitle
        }
    }
}

/// 灵动岛窗口相关本地设置。
@MainActor
final class IslandSettings: ObservableObject {
    static let shared = IslandSettings()

    enum Defaults {
        static let animationSpeed = 1.0
        static let hideInFullscreen = false
        static let hapticIntensity = IslandHapticIntensity.medium
        /// 稿面「默认」档：24 pt。
        static let bottomCornerRadius = 24.0
        /// 展开宽度（pt，逻辑像素）。
        static let expandedWidth: Double = 400
        static let theme = IslandTheme.midnight
        static let displayStyle = IslandDisplayStyle.notch
    }

    /// 设置滑块范围（pt）；运行时还会按屏幕再钳制。
    static let expandedWidthRange: ClosedRange<Double> = 240...900

    /// 展开高度 = 刘海高 × 此倍率；固定不可调。
    static let fixedExpandedHeightScale: Double = 3.0

    private enum Key {
        static let animationSpeed = "island.animationSpeed"
        static let hideInFullscreen = "island.hideInFullscreen"
        static let hapticIntensity = "island.hapticIntensity"
        static let hapticFeedbackLegacy = "island.hapticFeedback"
        static let displayStyle = "island.displayStyle"
        static let bottomCornerRadius = "island.bottomCornerRadius"
        static let expandedWidth = "island.expandedWidth"
        static let theme = "island.theme"
        /// 旧版倍率 key，仅用于迁移。
        static let expandedWidthScaleLegacy = "island.expandedWidthScale"
        /// 一次性：全屏禁用改为默认关。
        static let hideFullscreenDefaultOff = "island.hideFullscreenDefaultOff.v1"
    }

    /// 动画速度倍率：1.0 = 默认 0.35s；越大越快。范围 0.5…2.0
    @Published var animationSpeed: Double {
        didSet { UserDefaults.standard.set(animationSpeed, forKey: Key.animationSpeed) }
    }

    /// 全屏时禁用灵动岛；默认关闭。
    @Published var hideInFullscreen: Bool {
        didSet { UserDefaults.standard.set(hideInFullscreen, forKey: Key.hideInFullscreen) }
    }

    /// 展开/收起震感档位。
    @Published var hapticIntensity: IslandHapticIntensity {
        didSet { UserDefaults.standard.set(hapticIntensity.rawValue, forKey: Key.hapticIntensity) }
    }

    /// 下圆角半径（pt）；上边两角固定直角。
    @Published var bottomCornerRadius: Double {
        didSet { UserDefaults.standard.set(bottomCornerRadius, forKey: Key.bottomCornerRadius) }
    }

    /// 展开宽度（pt）。
    @Published var expandedWidth: Double {
        didSet {
            let clamped = min(
                max(expandedWidth, Self.expandedWidthRange.lowerBound),
                Self.expandedWidthRange.upperBound
            )
            if clamped != expandedWidth {
                expandedWidth = clamped
                return
            }
            UserDefaults.standard.set(expandedWidth, forKey: Key.expandedWidth)
        }
    }

    /// 预设配色主题。
    @Published var theme: IslandTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Key.theme) }
    }

    /// 展示形态：刘海 / 菜单栏下方胶囊。
    @Published var displayStyle: IslandDisplayStyle {
        didSet { UserDefaults.standard.set(displayStyle.rawValue, forKey: Key.displayStyle) }
    }

    var springDuration: Double {
        0.35 / max(animationSpeed, 0.25)
    }

    var springDamping: Double { 0.8 }

    func restoreDefaults() {
        animationSpeed = Defaults.animationSpeed
        hideInFullscreen = Defaults.hideInFullscreen
        hapticIntensity = Defaults.hapticIntensity
        bottomCornerRadius = Defaults.bottomCornerRadius
        expandedWidth = Defaults.expandedWidth
        theme = Defaults.theme
        displayStyle = Defaults.displayStyle
        AppLog.info("Settings", "已恢复默认设置")
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.animationSpeed) == nil {
            defaults.set(Defaults.animationSpeed, forKey: Key.animationSpeed)
        }
        if defaults.object(forKey: Key.hideFullscreenDefaultOff) == nil {
            defaults.set(Defaults.hideInFullscreen, forKey: Key.hideInFullscreen)
            defaults.set(true, forKey: Key.hideFullscreenDefaultOff)
        } else if defaults.object(forKey: Key.hideInFullscreen) == nil {
            defaults.set(Defaults.hideInFullscreen, forKey: Key.hideInFullscreen)
        }
        if defaults.object(forKey: Key.hapticIntensity) == nil {
            if defaults.object(forKey: Key.hapticFeedbackLegacy) != nil,
               defaults.bool(forKey: Key.hapticFeedbackLegacy) == false {
                defaults.set(IslandHapticIntensity.off.rawValue, forKey: Key.hapticIntensity)
            } else {
                defaults.set(Defaults.hapticIntensity.rawValue, forKey: Key.hapticIntensity)
            }
        }
        if defaults.object(forKey: Key.displayStyle) == nil {
            defaults.set(Defaults.displayStyle.rawValue, forKey: Key.displayStyle)
        }
        // 旧版「截屏可见」开关已废弃：岛窗口固定可被截屏/录屏捕获。
        defaults.removeObject(forKey: "island.showInScreenRecordings")
        if defaults.object(forKey: Key.bottomCornerRadius) == nil {
            defaults.set(Defaults.bottomCornerRadius, forKey: Key.bottomCornerRadius)
        }
        if defaults.object(forKey: Key.expandedWidth) == nil {
            // 从旧倍率迁到绝对宽度：按约 200pt 刘海估算。
            if defaults.object(forKey: Key.expandedWidthScaleLegacy) != nil {
                let scale = defaults.double(forKey: Key.expandedWidthScaleLegacy)
                let migrated = (scale * 200).rounded()
                let clamped = min(
                    max(migrated, Self.expandedWidthRange.lowerBound),
                    Self.expandedWidthRange.upperBound
                )
                defaults.set(clamped, forKey: Key.expandedWidth)
                AppLog.info("Settings", "展开宽度已从倍率迁移为 pt", [
                    "scale": scale,
                    "width": clamped
                ])
            } else {
                defaults.set(Defaults.expandedWidth, forKey: Key.expandedWidth)
            }
        }
        if defaults.object(forKey: Key.theme) == nil {
            defaults.set(Defaults.theme.rawValue, forKey: Key.theme)
        }

        animationSpeed = defaults.double(forKey: Key.animationSpeed)
        hideInFullscreen = defaults.bool(forKey: Key.hideInFullscreen)
        let hapticRaw = defaults.integer(forKey: Key.hapticIntensity)
        hapticIntensity = IslandHapticIntensity(rawValue: hapticRaw) ?? Defaults.hapticIntensity
        bottomCornerRadius = defaults.double(forKey: Key.bottomCornerRadius)
        let loadedWidth = defaults.double(forKey: Key.expandedWidth)
        expandedWidth = min(
            max(loadedWidth, Self.expandedWidthRange.lowerBound),
            Self.expandedWidthRange.upperBound
        )
        let themeRaw = defaults.string(forKey: Key.theme) ?? Defaults.theme.rawValue
        theme = IslandTheme(rawValue: themeRaw) ?? Defaults.theme
        let styleRaw = defaults.string(forKey: Key.displayStyle) ?? Defaults.displayStyle.rawValue
        displayStyle = IslandDisplayStyle(rawValue: styleRaw) ?? Defaults.displayStyle

        AppLog.debug("Settings", "已加载岛设置", [
            "speed": animationSpeed,
            "hideFullscreen": hideInFullscreen,
            "haptic": hapticIntensity.rawValue,
            "bottomRadius": bottomCornerRadius,
            "expandedWidth": expandedWidth,
            "theme": theme.rawValue,
            "heightScale": Self.fixedExpandedHeightScale,
            "style": displayStyle.rawValue
        ])
    }
}
