import SwiftUI

/// 接入 / 满电 / 低电：电量页与外设提示页共用同一套开关（展示顺序与预览 Tab 一致）。
struct BatteryAlertOptionsCard: View {
    @ObservedObject private var settings = BatterySettings.shared

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSwitchRow(
                    title: L10n.PeripheralTip.connectToggle,
                    subtitle: L10n.PeripheralTip.connectSubtitle,
                    isOn: $settings.connectAlertEnabled
                )

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
                    title: L10n.PeripheralTip.lowToggle,
                    subtitle: L10n.PeripheralTip.lowSubtitle,
                    isOn: $settings.lowAlertEnabled
                )

                thresholdRow
            }
        }
    }

    /// 与会议「提前提醒时间」同款：标题说明在上，整行浅底分段在下。
    private var thresholdRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Battery.lowThreshold)
                        .font(SettingsChrome.Font.rowTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Battery.lowThresholdSubtitle)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(L10n.Battery.lowThresholdBadge(settings.lowThresholdPercent))
                    .font(SettingsChrome.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(SettingsChrome.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SettingsChrome.primary.opacity(0.10))
                    )
            }

            HStack(spacing: 4) {
                ForEach(BatterySettings.lowThresholdPresets, id: \.self) { percent in
                    let selected = settings.lowThresholdPercent == percent
                    Button {
                        settings.lowThresholdPercent = percent
                    } label: {
                        Text(L10n.Battery.lowThresholdPresetLabel(percent))
                            .font(SettingsChrome.Font.chip)
                            .fontWeight(selected ? .semibold : .medium)
                            .foregroundStyle(selected ? SettingsChrome.onSurface : SettingsChrome.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selected ? Color.white : Color.clear)
                                    .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                    )
            )
        }
        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
        .padding(.vertical, 10)
    }
}
