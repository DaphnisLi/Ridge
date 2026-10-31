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

    enum Defaults {
        static let animationSpeed = 1.0
        static let hideInFullscreen = false
        static let hapticIntensity = IslandHapticIntensity.medium
        static let bottomCornerRadius = 18.0
        /// 展开宽度（pt，逻辑像素）。
        static let expandedWidth: Double = 400
        static let displayStyle = IslandDisplayStyle.notch
        static let showInScreenRecordings = false
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
        static let showInScreenRecordings = "island.showInScreenRecordings"
        static let bottomCornerRadius = "island.bottomCornerRadius"
        static let expandedWidth = "island.expandedWidth"
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

    func restoreDefaults() {
        animationSpeed = Defaults.animationSpeed
        hideInFullscreen = Defaults.hideInFullscreen
        hapticIntensity = Defaults.hapticIntensity
        bottomCornerRadius = Defaults.bottomCornerRadius
        expandedWidth = Defaults.expandedWidth
        displayStyle = Defaults.displayStyle
        showInScreenRecordings = Defaults.showInScreenRecordings
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
        if defaults.object(forKey: Key.showInScreenRecordings) == nil {
            defaults.set(Defaults.showInScreenRecordings, forKey: Key.showInScreenRecordings)
        }
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
        let styleRaw = defaults.string(forKey: Key.displayStyle) ?? Defaults.displayStyle.rawValue
        displayStyle = IslandDisplayStyle(rawValue: styleRaw) ?? Defaults.displayStyle
        showInScreenRecordings = defaults.bool(forKey: Key.showInScreenRecordings)

        AppLog.debug("Settings", "已加载岛设置", [
            "speed": animationSpeed,
            "hideFullscreen": hideInFullscreen,
            "haptic": hapticIntensity.rawValue,
            "bottomRadius": bottomCornerRadius,
            "expandedWidth": expandedWidth,
            "heightScale": Self.fixedExpandedHeightScale,
            "style": displayStyle.rawValue
        ])
    }
}
