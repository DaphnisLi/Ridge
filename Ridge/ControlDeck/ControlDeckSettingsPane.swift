import SwiftUI

/// 设置侧栏「控制台」：开关与能力说明；不与小组件库混排。
struct ControlDeckSettingsPane: View {
    @ObservedObject private var settings = ControlDeckSettings.shared
    @ObservedObject private var soundSettings = SoundSettings.shared
    @ObservedObject private var sound = SoundSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introCard
                enableCard
                mixerPrefsCard
                modulesCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            IslandController.shared?.beginSettingsSessionCollapsed()
            AppLog.debug("ControlDeck", "控制台设置页已显示", ["enabled": settings.isEnabled])
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.ControlDeck.title)
                .font(.system(size: 22, weight: .semibold))
            Text(L10n.ControlDeck.intro)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.ControlDeck.showOnIsland)
                        .font(.system(size: 14, weight: .semibold))
                    Text(settings.isEnabled
                         ? L10n.ControlDeck.enabledHint
                         : L10n.ControlDeck.disabledHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { enabled in
                            settings.setEnabled(enabled)
                            if enabled {
                                WidgetRuntime.shared.focusControlDeck()
                            } else {
                                WidgetRuntime.shared.recompute(reason: "controlDeckOff")
                            }
                            IslandController.shared?.beginSettingsSessionCollapsed()
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if settings.isEnabled {
                Button {
                    WidgetRuntime.shared.focusControlDeck()
                    IslandController.shared?.beginSettingsSession()
                    AppLog.info("ControlDeck", "设置页预览控制台")
                } label: {
                    Label(L10n.ControlDeck.previewOnIsland, systemImage: "rectangle.portrait.on.rectangle.portrait")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
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

    private var mixerPrefsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Sound.mixerPrefsTitle)
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.Sound.mixerPrefsIntro)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                SettingsSwitchRow(
                    title: L10n.Sound.rememberVolumes,
                    isOn: $soundSettings.rememberVolumes
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
            )

            HStack(spacing: 10) {
                if sound.tapAvailability == .needsScreenCapture {
                    Button(L10n.Sound.grantScreenCapture) {
                        sound.requestScreenCaptureAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Button(L10n.Sound.resetAppVolumes) {
                    sound.resetAppVolumes()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
        .onAppear { sound.start() }
    }

    private var modulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.ControlDeck.plannedModules)
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.ControlDeck.plannedIntro)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(settings.plannedModules) { module in
                    moduleRow(module)
                }
            }
        }
        .padding(16)
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

    private func moduleRow(_ module: ControlDeckPlannedModule) -> some View {
        let isLive = module.id == "volume"
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: module.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 13, weight: .medium))
                Text(module.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(isLive ? L10n.Sound.moduleLive : L10n.Common.comingSoon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isLive ? AnyShapeStyle(SettingsChrome.secondary) : AnyShapeStyle(.tertiary))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke.opacity(0.85), lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
    }
}
