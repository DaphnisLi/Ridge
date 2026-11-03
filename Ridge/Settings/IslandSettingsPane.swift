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
                VStack(alignment: .leading, spacing: 14) {
                    themeCard
                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                        GridRow(alignment: .top) {
                            geometryCard
                            motionCard
                        }
                    }
                    fullscreenCard
                }
                .padding(.horizontal, 28)
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
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 28)
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
        bentoCard {
            HStack(alignment: .firstTextBaseline) {
                cardTitle(
                    symbol: "paintpalette.fill",
                    tint: SettingsChrome.primary,
                    title: L10n.Settings.presetTheme,
                    badge: L10n.Settings.themeCountBadge
                )
                Spacer(minLength: 8)
                Text(L10n.Settings.themeClickHint)
                    .font(.system(size: 11))
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
        bentoCard {
            HStack {
                cardTitle(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    tint: Color(red: 0.35, green: 0.40, blue: 0.95),
                    title: L10n.Settings.geometryTitle
                )
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(L10n.Settings.matrixLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    Text("\(Int(settings.expandedWidth.rounded())) pt × \(Int(settings.bottomCornerRadius.rounded())) pt")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurface)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(SettingsChrome.surfaceContainer.opacity(0.9)))
            }

            geometryPresetBar

            VStack(spacing: 14) {
                bentoSlider(
                    title: L10n.Settings.expandedWidth,
                    valueText: "\(Int(settings.expandedWidth.rounded())) pt",
                    value: $settings.expandedWidth,
                    range: IslandSettings.expandedWidthRange,
                    step: 5,
                    leading: "\(L10n.Settings.widthNarrow) (\(Int(IslandSettings.expandedWidthRange.lowerBound)))",
                    trailing: "\(L10n.Settings.widthWide) (\(Int(IslandSettings.expandedWidthRange.upperBound)))"
                )
                bentoSlider(
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
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 8)
                geometryMiniPreview
            }
            .padding(.top, 4)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 1)
                    .padding(.top, -8)
            }
        }
    }

    private var geometryPresetBar: some View {
        let active = matchedGeometryPreset
        return HStack(spacing: 6) {
            geometryPresetButton(.compact, title: L10n.Settings.presetCompact, active: active)
            geometryPresetButton(.balanced, title: L10n.Settings.presetBalanced, active: active)
            geometryPresetButton(.wide, title: L10n.Settings.presetWide, active: active)
            Text(L10n.Settings.presetCustom)
                .font(.system(size: 11, weight: active == .custom ? .semibold : .medium))
                .foregroundStyle(active == .custom ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active == .custom ? Color.white : Color.clear)
                        .shadow(color: active == .custom ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainer.opacity(0.7))
        )
    }

    private func geometryPresetButton(
        _ preset: GeometryPreset,
        title: String,
        active: GeometryPreset
    ) -> some View {
        let selected = active == preset
        return Button {
            if let width = preset.width { settings.expandedWidth = width }
            if let radius = preset.radius { settings.bottomCornerRadius = radius }
            AppLog.info("Settings", "几何预设", ["preset": "\(preset)"])
        } label: {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.white : Color.clear)
                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
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
        bentoCard {
            HStack {
                cardTitle(
                    symbol: "waveform.path",
                    tint: Color(red: 0.95, green: 0.45, blue: 0.20),
                    title: L10n.Settings.motionTitle
                )
                Spacer(minLength: 8)
                Text(speedTagText)
                    .font(.system(size: 10, design: .monospaced))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f×", settings.animationSpeed))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }

                HStack(spacing: 6) {
                    ForEach(SpeedPreset.allCases, id: \.rawValue) { preset in
                        let selected = matchedSpeedPreset == preset
                        Button {
                            settings.animationSpeed = preset.rawValue
                            AppLog.info("Settings", "动画速度预设", ["speed": preset.rawValue])
                        } label: {
                            Text("\(preset.title) (\(String(format: "%.1f×", preset.rawValue)))")
                                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected ? Color.white : Color.clear)
                                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsChrome.surfaceContainer.opacity(0.7))
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
                .font(.system(size: 10))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(L10n.Settings.hapticIntensity)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text("(\(L10n.Settings.hapticTapticHint))")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    Circle()
                        .fill(SettingsChrome.secondary)
                        .frame(width: 6, height: 6)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    ForEach(IslandHapticIntensity.allCases) { level in
                        let selected = settings.hapticIntensity == level
                        Button {
                            settings.hapticIntensity = level
                        } label: {
                            Text(level.title)
                                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected ? Color.white : Color.clear)
                                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsChrome.surfaceContainer.opacity(0.7))
                )
            }
            .padding(.top, 6)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Fullscreen

    private var fullscreenCard: some View {
        bentoCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.90, green: 0.98, blue: 0.93))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.65, blue: 0.40))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.Settings.hideInFullscreen)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Settings.hideFullscreenBadge)
                            .font(.system(size: 10))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SettingsChrome.surfaceContainer))
                    }
                    Text(L10n.Settings.hideFullscreenSubtitle)
                        .font(.system(size: 11))
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

    // MARK: - Shared chrome

    private func bentoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
        )
    }

    private func cardTitle(
        symbol: String,
        tint: Color,
        title: String,
        badge: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsChrome.onSurface)

            if let badge {
                Text(badge)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
            }
        }
    }

    private func bentoSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        leading: String,
        trailing: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainerLow)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(SettingsChrome.outline.opacity(0.55), lineWidth: 1)
                            )
                    )
            }
            // 不用 step，避免 macOS Slider 在轨道下画出刻度点；松手时按 step 取整。
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { next in
                        let snapped = (next / step).rounded() * step
                        value.wrappedValue = min(max(snapped, range.lowerBound), range.upperBound)
                    }
                ),
                in: range
            )
            HStack {
                Text(leading)
                Spacer(minLength: 0)
                Text(trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(SettingsChrome.onSurfaceVariant)
        }
    }
}

// MARK: - 布局组件（仿系统触控板设置；其它设置页复用）

struct SettingsPaneSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            SettingsCard { content }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsChrome.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                    )
            )
    }
}

struct SettingsFormRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
    }
}

struct SettingsGroupedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        SettingsFormRows { content }
    }
}

struct SettingsSwitchRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if selected {
                        Text(L10n.Settings.themeInUse)
                            .font(.system(size: 9, weight: .medium))
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
