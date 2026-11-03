import SwiftUI

struct IslandSettingsPane: View {
    @ObservedObject var settings: IslandSettings

    private enum GeometryPreset: Equatable {
        case compact
        case balanced
        case wide
        case custom

        var width: Double? {
            switch self {
            case .compact: return 320
            case .balanced: return 400
            case .wide: return 520
            case .custom: return nil
            }
        }

        var radius: Double? {
            switch self {
            case .compact: return 12
            case .balanced: return 18
            case .wide: return 24
            case .custom: return nil
            }
        }
    }

    private enum SpeedPreset: Double, CaseIterable {
        case snap = 0.6
        case standard = 1.0
        case smooth = 1.6

        var title: String {
            switch self {
            case .snap: return L10n.Settings.speedSnap
            case .standard: return L10n.Settings.speedStandard
            case .smooth: return L10n.Settings.speedSmooth
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                // 标题 / 说明在顶栏左上，页内从主题卡开始。
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    themeCard
                    Grid(horizontalSpacing: SettingsChrome.Spacing.stack, verticalSpacing: SettingsChrome.Spacing.stack) {
                        GridRow(alignment: .top) {
                            geometryCard
                            motionCard
                        }
                    }
                    fullscreenCard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            guard MenuBarController.shared?.settingsWindow != nil else { return }
            IslandController.shared?.beginSettingsSession()
            AppLog.debug("Settings", "灵动岛设置页已显示")
        }
        .onChange(of: settings.animationSpeed) { _, value in
            AppLog.info("Settings", "动画速度已更新", ["speed": value])
        }
        .onChange(of: settings.hideInFullscreen) { _, value in
            AppLog.info("Settings", "全屏禁用岛", ["enabled": value])
        }
        .onChange(of: settings.hapticIntensity) { _, value in
            AppLog.info("Settings", "震感强度", ["level": value.rawValue])
            IslandHaptics.play(value)
        }
        .onChange(of: settings.bottomCornerRadius) { _, value in
            AppLog.info("Settings", "下圆角已更新", ["radius": value])
        }
        .onChange(of: settings.expandedWidth) { _, value in
            AppLog.info("Settings", "展开宽度", ["width": value])
        }
        .onChange(of: settings.theme) { _, value in
            AppLog.info("Settings", "预设主题", ["theme": value.rawValue])
        }
    }

    // MARK: - Header / Footer

    private var footerBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                settings.restoreDefaults()
                AppLog.info("Settings", "已恢复默认设置")
            } label: {
                Label(L10n.Common.restoreDefaults, systemImage: "arrow.counterclockwise")
                    .font(SettingsChrome.Font.label)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
        .padding(.vertical, 12)
        .background(SettingsChrome.pageBackground.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }

    // MARK: - Theme

    private var themeCard: some View {
        SettingsBentoCard {
            HStack(alignment: .firstTextBaseline) {
                SettingsBentoCardTitle(
                    symbol: "paintpalette.fill",
                    tint: SettingsChrome.primary,
                    title: L10n.Settings.presetTheme,
                    badge: L10n.Settings.themeCountBadge
                )
                Spacer(minLength: 8)
                Text(L10n.Settings.themeClickHint)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            HStack(spacing: 10) {
                ForEach(IslandTheme.allCases) { theme in
                    IslandThemeChip(
                        theme: theme,
                        selected: settings.theme == theme
                    ) {
                        settings.theme = theme
                    }
                }
            }
        }
    }

    // MARK: - Geometry

    private var matchedGeometryPreset: GeometryPreset {
        for preset: GeometryPreset in [.compact, .balanced, .wide] {
            if abs((preset.width ?? -1) - settings.expandedWidth) < 0.5,
               abs((preset.radius ?? -1) - settings.bottomCornerRadius) < 0.5 {
                return preset
            }
        }
        return .custom
    }

    private var geometryCard: some View {
        SettingsBentoCard {
            HStack {
                SettingsBentoCardTitle(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    tint: Color(red: 0.35, green: 0.40, blue: 0.95),
                    title: L10n.Settings.geometryTitle
                )
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(L10n.Settings.matrixLabel)
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    Text("\(Int(settings.expandedWidth.rounded())) pt × \(Int(settings.bottomCornerRadius.rounded())) pt")
                        .font(SettingsChrome.Font.monoEmphasis)
                        .foregroundStyle(SettingsChrome.onSurface)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(SettingsChrome.surfaceContainer.opacity(0.9)))
            }

            geometryPresetBar

            VStack(spacing: SettingsChrome.Spacing.stack) {
                SettingsSliderRow(
                    title: L10n.Settings.expandedWidth,
                    valueText: "\(Int(settings.expandedWidth.rounded())) pt",
                    value: $settings.expandedWidth,
                    range: IslandSettings.expandedWidthRange,
                    step: 5,
                    leading: "\(L10n.Settings.widthNarrow) (\(Int(IslandSettings.expandedWidthRange.lowerBound)))",
                    trailing: "\(L10n.Settings.widthWide) (\(Int(IslandSettings.expandedWidthRange.upperBound)))"
                )
                SettingsSliderRow(
                    title: L10n.Settings.bottomCorner,
                    valueText: "\(Int(settings.bottomCornerRadius.rounded())) pt",
                    value: $settings.bottomCornerRadius,
                    range: 0...36,
                    step: 1,
                    leading: "\(L10n.Settings.cornerSquare) (0 pt)",
                    trailing: "\(L10n.Settings.cornerRound) (36 pt)"
                )
            }

            HStack {
                Text(L10n.Settings.geometryPreview)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 8)
                geometryMiniPreview
            }
            .padding(.top, 4)
            .overlay(alignment: .top) {
                SettingsHairline()
                    .padding(.top, -8)
            }
        }
    }

    private var geometryPresetBar: some View {
        let active = matchedGeometryPreset
        return SettingsSegmentedControl(items: [
            .init(
                id: "compact",
                title: L10n.Settings.presetCompact,
                selected: active == .compact
            ) {
                if let width = GeometryPreset.compact.width { settings.expandedWidth = width }
                if let radius = GeometryPreset.compact.radius { settings.bottomCornerRadius = radius }
                AppLog.info("Settings", "几何预设", ["preset": "compact"])
            },
            .init(
                id: "balanced",
                title: L10n.Settings.presetBalanced,
                selected: active == .balanced
            ) {
                if let width = GeometryPreset.balanced.width { settings.expandedWidth = width }
                if let radius = GeometryPreset.balanced.radius { settings.bottomCornerRadius = radius }
                AppLog.info("Settings", "几何预设", ["preset": "balanced"])
            },
            .init(
                id: "wide",
                title: L10n.Settings.presetWide,
                selected: active == .wide
            ) {
                if let width = GeometryPreset.wide.width { settings.expandedWidth = width }
                if let radius = GeometryPreset.wide.radius { settings.bottomCornerRadius = radius }
                AppLog.info("Settings", "几何预设", ["preset": "wide"])
            },
            .init(
                id: "custom",
                title: L10n.Settings.presetCustom,
                selected: active == .custom,
                isInteractive: false,
                action: {}
            ),
        ])
    }

    private var geometryMiniPreview: some View {
        let palette = settings.theme.palette
        let previewW = 80 + (settings.expandedWidth - IslandSettings.expandedWidthRange.lowerBound)
            * (100 / max(IslandSettings.expandedWidthRange.upperBound - IslandSettings.expandedWidthRange.lowerBound, 1))
        let radius = min(max(settings.bottomCornerRadius, 0), 24)
        return HStack(spacing: 6) {
            Circle()
                .fill(palette.icon)
                .frame(width: 6, height: 6)
            Capsule()
                .fill(palette.accentFill.opacity(0.7))
                .frame(width: 24, height: 4)
        }
        .padding(.horizontal, 10)
        .frame(width: min(max(previewW, 72), 180), height: 20)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: 4,
                style: .continuous
            )
            .fill(palette.fill)
        )
        .animation(.easeOut(duration: 0.15), value: settings.expandedWidth)
        .animation(.easeOut(duration: 0.15), value: settings.bottomCornerRadius)
        .animation(.easeOut(duration: 0.15), value: settings.theme)
    }

    // MARK: - Motion / Haptic

    private var matchedSpeedPreset: SpeedPreset? {
        SpeedPreset.allCases.first { abs($0.rawValue - settings.animationSpeed) < 0.05 }
    }

    private var speedTagText: String {
        let value = String(format: "%.1f×", settings.animationSpeed)
        if let preset = matchedSpeedPreset {
            return "\(value) \(preset.title)"
        }
        return "\(value) \(L10n.Settings.presetCustom)"
    }

    private var motionCard: some View {
        SettingsBentoCard {
            HStack {
                SettingsBentoCardTitle(
                    symbol: "waveform.path",
                    tint: Color(red: 0.95, green: 0.45, blue: 0.20),
                    title: L10n.Settings.motionTitle
                )
                Spacer(minLength: 8)
                Text(speedTagText)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.Settings.animationSpeed)
                        .font(SettingsChrome.Font.label)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f×", settings.animationSpeed))
                        .font(SettingsChrome.Font.monoLabel)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }

                SettingsSegmentedControl(
                    items: SpeedPreset.allCases.map { preset in
                        .init(
                            id: "\(preset.rawValue)",
                            title: "\(preset.title) (\(String(format: "%.1f×", preset.rawValue)))",
                            selected: matchedSpeedPreset == preset
                        ) {
                            settings.animationSpeed = preset.rawValue
                            AppLog.info("Settings", "动画速度预设", ["speed": preset.rawValue])
                        }
                    }
                )

                // 不用 step，避免 macOS Slider 在轨道下画出刻度点。
                Slider(
                    value: Binding(
                        get: { settings.animationSpeed },
                        set: { settings.animationSpeed = ($0 * 10).rounded() / 10 }
                    ),
                    in: 0.5...2.0
                )
                HStack {
                    Text("\(L10n.Settings.speedSlow) (0.5×)")
                    Spacer(minLength: 0)
                    Text("\(L10n.Settings.speedFast) (2.0×)")
                }
                .font(SettingsChrome.Font.footnote)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(L10n.Settings.hapticIntensity)
                        .font(SettingsChrome.Font.label)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text("(\(L10n.Settings.hapticTapticHint))")
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    Circle()
                        .fill(SettingsChrome.secondary)
                        .frame(width: 6, height: 6)
                    Spacer(minLength: 0)
                }

                SettingsSegmentedControl(
                    items: IslandHapticIntensity.allCases.map { level in
                        .init(
                            id: "\(level.rawValue)",
                            title: level.title,
                            selected: settings.hapticIntensity == level
                        ) {
                            settings.hapticIntensity = level
                        }
                    }
                )
            }
            .padding(.top, 6)
            .overlay(alignment: .top) {
                SettingsHairline()
            }
        }
    }

    // MARK: - Fullscreen

    private var fullscreenCard: some View {
        SettingsBentoCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.90, green: 0.98, blue: 0.93))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(SettingsChrome.Font.iconTile)
                        .foregroundStyle(Color(red: 0.16, green: 0.65, blue: 0.40))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.Settings.hideInFullscreen)
                            .font(SettingsChrome.Font.cardTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Settings.hideFullscreenBadge)
                            .font(SettingsChrome.Font.micro)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SettingsChrome.surfaceContainer))
                    }
                    Text(L10n.Settings.hideFullscreenSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $settings.hideInFullscreen)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

}

private struct IslandThemeChip: View {
    let theme: IslandTheme
    let selected: Bool
    let action: () -> Void

    private var palette: IslandPalette { theme.palette }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IslandThemeSwatch(palette: palette)

                HStack(spacing: 4) {
                    Text(theme.title)
                        .font(selected ? SettingsChrome.Font.chipSelected : SettingsChrome.Font.chip)
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if selected {
                        Text(L10n.Settings.themeInUse)
                            .font(SettingsChrome.Font.badgeTiny)
                            .foregroundStyle(SettingsChrome.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(SettingsChrome.primary.opacity(0.12))
                            )
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? SettingsChrome.primary.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? SettingsChrome.primary : Color.black.opacity(0.05),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct IslandThemeSwatch: View {
    let palette: IslandPalette

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: 10)
        HStack(spacing: 6) {
            Circle()
                .fill(palette.icon)
                .frame(width: 8, height: 8)
                .shadow(color: palette.icon.opacity(0.55), radius: 3)
            Capsule()
                .fill(palette.accentFill.opacity(0.8))
                .frame(width: 28, height: 4)
            Capsule()
                .fill(palette.secondary.opacity(0.45))
                .frame(width: 14, height: 4)
            Spacer(minLength: 0)
            Text("•••")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.secondary.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(shape.fill(palette.fill))
        .clipShape(shape)
        .overlay(
            shape.stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
