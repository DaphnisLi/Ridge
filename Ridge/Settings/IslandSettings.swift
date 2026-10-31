import Combine
import CoreGraphics
import Foundation

enum IslandDisplayStyle: String, CaseIterable, Identifiable {
    case notch
    case pillBelowMenuBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "刘海"
        case .pillBelowMenuBar: return "菜单栏下方胶囊"
        }
    }

    var subtitle: String {
        switch self {
        case .notch: return "贴合刘海，悬停展开"
        case .pillBelowMenuBar: return "浮在菜单栏下方（即将支持）"
        }
    }
}

/// 灵动岛窗口相关本地设置。
@MainActor
final class IslandSettings: ObservableObject {
    static let shared = IslandSettings()

    private enum Key {
        static let animationSpeed = "island.animationSpeed"
        static let hideInFullscreen = "island.hideInFullscreen"
        static let hapticIntensity = "island.hapticIntensity"
        static let hapticFeedbackLegacy = "island.hapticFeedback"
        static let displayStyle = "island.displayStyle"
        static let showInScreenRecordings = "island.showInScreenRecordings"
        static let bottomCornerRadius = "island.bottomCornerRadius"
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

    /// 展示形态：刘海 / 菜单栏下方胶囊。
    @Published var displayStyle: IslandDisplayStyle {
        didSet { UserDefaults.standard.set(displayStyle.rawValue, forKey: Key.displayStyle) }
    }

    /// 是否出现在屏幕录制中。
    @Published var showInScreenRecordings: Bool {
        didSet { UserDefaults.standard.set(showInScreenRecordings, forKey: Key.showInScreenRecordings) }
    }

    var springDuration: Double {
        0.35 / max(animationSpeed, 0.25)
    }

    var springDamping: Double { 0.8 }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.animationSpeed) == nil {
            defaults.set(1.0, forKey: Key.animationSpeed)
        }
        if defaults.object(forKey: Key.hideFullscreenDefaultOff) == nil {
            defaults.set(false, forKey: Key.hideInFullscreen)
            defaults.set(true, forKey: Key.hideFullscreenDefaultOff)
        } else if defaults.object(forKey: Key.hideInFullscreen) == nil {
            defaults.set(false, forKey: Key.hideInFullscreen)
        }
        if defaults.object(forKey: Key.hapticIntensity) == nil {
            // 迁移旧开关；默认「强」
            if defaults.object(forKey: Key.hapticFeedbackLegacy) != nil,
               defaults.bool(forKey: Key.hapticFeedbackLegacy) == false {
                defaults.set(IslandHapticIntensity.off.rawValue, forKey: Key.hapticIntensity)
            } else {
                defaults.set(IslandHapticIntensity.strong.rawValue, forKey: Key.hapticIntensity)
            }
        }
        if defaults.object(forKey: Key.displayStyle) == nil {
            defaults.set(IslandDisplayStyle.notch.rawValue, forKey: Key.displayStyle)
        }
        if defaults.object(forKey: Key.showInScreenRecordings) == nil {
            defaults.set(false, forKey: Key.showInScreenRecordings)
        }
        if defaults.object(forKey: Key.bottomCornerRadius) == nil {
            defaults.set(18.0, forKey: Key.bottomCornerRadius)
        }

        animationSpeed = defaults.double(forKey: Key.animationSpeed)
        hideInFullscreen = defaults.bool(forKey: Key.hideInFullscreen)
        let hapticRaw = defaults.integer(forKey: Key.hapticIntensity)
        hapticIntensity = IslandHapticIntensity(rawValue: hapticRaw) ?? .strong
        bottomCornerRadius = defaults.double(forKey: Key.bottomCornerRadius)
        let styleRaw = defaults.string(forKey: Key.displayStyle) ?? IslandDisplayStyle.notch.rawValue
        displayStyle = IslandDisplayStyle(rawValue: styleRaw) ?? .notch
        showInScreenRecordings = defaults.bool(forKey: Key.showInScreenRecordings)

        AppLog.debug("Settings", "已加载岛设置", [
            "speed": animationSpeed,
            "hideFullscreen": hideInFullscreen,
            "haptic": hapticIntensity.rawValue,
            "bottomRadius": bottomCornerRadius,
            "style": displayStyle.rawValue
        ])
    }
}
