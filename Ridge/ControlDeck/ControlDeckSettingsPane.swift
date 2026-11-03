import AppKit
import SwiftUI

/// 设置侧栏「控制台」：模块开关 + 混音台 / 项目根目录选项。
struct ControlDeckSettingsPane: View {
    @ObservedObject private var settings = ControlDeckSettings.shared
    @ObservedObject private var soundSettings = SoundSettings.shared
    @ObservedObject private var sound = SoundSession.shared
    @ObservedObject private var projectSettings = ProjectSettings.shared
    @ObservedObject private var batterySettings = BatterySettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modulesCard
                if settings.isModuleEnabled("volume") {
                    mixerPrefsCard
                }
                if settings.isModuleEnabled("projects") {
                    projectRootsCard
                }
                if settings.isModuleEnabled("battery") {
                    batteryAlertsCard
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            IslandController.shared?.beginSettingsSessionCollapsed()
            AppLog.debug("ControlDeck", "控制台设置页已显示", ["enabled": settings.isEnabled])
        }
    }

    private var modulesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(settings.plannedModules) { module in
                moduleSwitchRow(module)
                if module.id != settings.plannedModules.last?.id {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
    }

    private func moduleSwitchRow(_ module: ControlDeckPlannedModule) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(module.isLive ? 0.12 : 0.06))
                Image(systemName: module.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(module.isLive ? Color.accentColor : Color.secondary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(module.isLive ? Color.primary : Color.secondary)
                if !module.isLive {
                    Text(L10n.Common.comingSoon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { settings.isModuleEnabled(module.id) },
                    set: { enabled in
                        settings.setModuleEnabled(module.id, enabled)
                        IslandController.shared?.beginSettingsSessionCollapsed()
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!module.isLive)
            .opacity(module.isLive ? 1 : 0.45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private var projectRootsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Projects.rootsTitle)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Button(L10n.Projects.addRoot) {
                    pickProjectRoot()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(L10n.Projects.rootsIntro)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                if projectSettings.roots.isEmpty {
                    Text(L10n.Projects.rootsEmpty)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(projectSettings.roots, id: \.self) { root in
                        HStack {
                            Text(root)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Button {
                                projectSettings.removeRoot(root)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if root != projectSettings.roots.last {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
            )
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

    private func pickProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.Projects.addRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectSettings.addRoot(url.path)
        AppLog.info("Projects", "设置页添加项目根目录")
    }

    private var batteryAlertsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Battery.alertsTitle)
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.Battery.alertsIntro)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                SettingsSwitchRow(
                    title: L10n.Battery.lowAlertToggle,
                    isOn: $batterySettings.lowAlertEnabled
                )
                Divider().padding(.leading, 14)
                SettingsSwitchRow(
                    title: L10n.Battery.fullAlertToggle,
                    isOn: $batterySettings.fullChargeAlertEnabled
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
            )

            if batterySettings.lowAlertEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.Battery.lowThreshold)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 8)
                        Text("\(batterySettings.lowThresholdPercent)%")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(batterySettings.lowThresholdPercent) },
                            set: { batterySettings.lowThresholdPercent = Int($0.rounded()) }
                        ),
                        in: 5...40,
                        step: 1
                    )
                    Text(L10n.Battery.lowThresholdHint(batterySettings.lowThresholdPercent))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.Battery.snoozeHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            if batterySettings.fullChargeAlertEnabled {
                Text(L10n.Battery.fullAlertHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
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
        .onAppear {
            BatterySession.shared.start()
            AppLog.debug("Battery", "电量告警设置卡已显示", [
                "low": batterySettings.lowAlertEnabled,
                "threshold": batterySettings.lowThresholdPercent,
                "full": batterySettings.fullChargeAlertEnabled
            ])
        }
    }
}
