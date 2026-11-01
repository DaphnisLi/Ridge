import SwiftUI

/// 灵动岛预设配色。
enum IslandTheme: String, CaseIterable, Identifiable, Hashable {
    case midnight
    case afterglow
    case lumenPark
    case graphite
    case tide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return L10n.Settings.themeMidnight
        case .afterglow: return L10n.Settings.themeAfterglow
        case .lumenPark: return L10n.Settings.themeLumenPark
        case .graphite: return L10n.Settings.themeGraphite
        case .tide: return L10n.Settings.themeTide
        }
    }

    var palette: IslandPalette {
        switch self {
        case .midnight:
            return IslandPalette(
                fill: .black,
                title: .white.opacity(0.9),
                secondary: .white.opacity(0.4),
                icon: .white.opacity(0.85),
                pageDotActive: .white.opacity(0.9),
                pageDotInactive: .white.opacity(0.22),
                accentFill: .white.opacity(0.92),
                accentForeground: .black.opacity(0.85)
            )
        case .afterglow:
            return IslandPalette(
                // 底色略抬亮并偏暖，设置样张里也能和纯黑区分。
                fill: Color(red: 0.22, green: 0.11, blue: 0.09),
                title: Color(red: 1.0, green: 0.93, blue: 0.88),
                secondary: Color(red: 0.92, green: 0.62, blue: 0.48).opacity(0.85),
                icon: Color(red: 0.98, green: 0.72, blue: 0.52),
                pageDotActive: Color(red: 0.98, green: 0.72, blue: 0.52),
                pageDotInactive: Color.white.opacity(0.22),
                accentFill: Color(red: 0.96, green: 0.68, blue: 0.48),
                accentForeground: Color(red: 0.18, green: 0.08, blue: 0.05)
            )
        case .lumenPark:
            return IslandPalette(
                fill: Color(red: 0.09, green: 0.18, blue: 0.13),
                title: Color(red: 0.90, green: 0.96, blue: 0.92),
                secondary: Color(red: 0.55, green: 0.78, blue: 0.62).opacity(0.9),
                icon: Color(red: 0.62, green: 0.86, blue: 0.70),
                pageDotActive: Color(red: 0.62, green: 0.86, blue: 0.70),
                pageDotInactive: Color.white.opacity(0.22),
                accentFill: Color(red: 0.72, green: 0.90, blue: 0.78),
                accentForeground: Color(red: 0.06, green: 0.14, blue: 0.09)
            )
        case .graphite:
            return IslandPalette(
                fill: Color(red: 0.18, green: 0.18, blue: 0.19),
                title: .white.opacity(0.92),
                secondary: .white.opacity(0.45),
                icon: .white.opacity(0.82),
                pageDotActive: .white.opacity(0.9),
                pageDotInactive: .white.opacity(0.24),
                accentFill: .white.opacity(0.92),
                accentForeground: Color(red: 0.12, green: 0.12, blue: 0.13)
            )
        case .tide:
            return IslandPalette(
                fill: Color(red: 0.06, green: 0.14, blue: 0.26),
                title: Color(red: 0.88, green: 0.94, blue: 1.0),
                secondary: Color(red: 0.45, green: 0.68, blue: 0.88).opacity(0.9),
                icon: Color(red: 0.55, green: 0.78, blue: 0.96),
                pageDotActive: Color(red: 0.55, green: 0.78, blue: 0.96),
                pageDotInactive: Color.white.opacity(0.22),
                accentFill: Color(red: 0.62, green: 0.82, blue: 0.98),
                accentForeground: Color(red: 0.05, green: 0.12, blue: 0.2)
            )
        }
    }
}

struct IslandPalette: Equatable {
    var fill: Color
    var title: Color
    var secondary: Color
    var icon: Color
    var pageDotActive: Color
    var pageDotInactive: Color
    var accentFill: Color
    var accentForeground: Color
}

private enum IslandPaletteKey: EnvironmentKey {
    static let defaultValue = IslandTheme.midnight.palette
}

extension EnvironmentValues {
    var islandPalette: IslandPalette {
        get { self[IslandPaletteKey.self] }
        set { self[IslandPaletteKey.self] = newValue }
    }
}
