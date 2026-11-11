import SwiftUI

/// 低电 / 阈值 / 满电 / 接入：电量页与外设提示页共用同一套开关。
struct BatteryAlertOptionsCard: View {
    @ObservedObject private var settings = BatterySettings.shared

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSwitchRow(
                    title: L10n.PeripheralTip.lowToggle,
                    subtitle: L10n.PeripheralTip.lowSubtitle,
                    isOn: $settings.lowAlertEnabled
                )

                thresholdRow

                SettingsHairline()
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)

                SettingsSwitchRow(
                    title: L10n.PeripheralTip.fullToggle,
                    subtitle: L10n.PeripheralTip.fullSubtitle,
                    isOn: $settings.fullChargeAlertEnabled
                )

                SettingsHairline()
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)

                SettingsSwitchRow(
                    title: L10n.PeripheralTip.connectToggle,
                    subtitle: L10n.PeripheralTip.connectSubtitle,
                    isOn: $settings.connectAlertEnabled
                )
            }
        }
    }

    private var thresholdRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Battery.lowThreshold)
                    .font(SettingsChrome.Font.rowTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Battery.lowThresholdSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsSegmentedControl(
                items: BatterySettings.lowThresholdPresets.map { percent in
                    let selected = settings.lowThresholdPercent == percent
                    return SettingsSegmentedControl.Item(
                        id: "battery-alert-threshold-\(percent)",
                        title: L10n.Battery.lowThresholdPresetLabel(percent),
                        selected: selected,
                        leadingDot: selected ? SettingsChrome.primary : nil
                    ) {
                        settings.lowThresholdPercent = percent
                    }
                }
            )
            .frame(width: 320)
        }
        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
        .padding(.vertical, 8)
    }
}
