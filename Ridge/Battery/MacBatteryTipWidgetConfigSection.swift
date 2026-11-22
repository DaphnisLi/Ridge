import SwiftUI

/// 本机电池 tip 设置：四态样张 + 低电阈值（分项提醒随小组件总开关）。
struct MacBatteryTipWidgetConfigSection: View {
    @ObservedObject private var settings = MacBatterySettings.shared
    @ObservedObject private var session = MacBatterySession.shared
    @State private var previewSelection = "charging"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    if !session.hasInternalBattery {
                        SettingsCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "laptopcomputer.slash")
                                    .font(SettingsChrome.Font.iconTile)
                                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.MacBattery.noBatteryTitle)
                                        .font(SettingsChrome.Font.cardTitle)
                                        .foregroundStyle(SettingsChrome.onSurface)
                                    Text(L10n.MacBattery.noBatterySubtitle)
                                        .font(SettingsChrome.Font.body)
                                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(SettingsChrome.Spacing.cardPadding)
                        }
                    }

                    previewStage
                    thresholdCard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreDefaults()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            MacBatterySession.shared.start()
            AppLog.info("MacBattery", "配置页已显示", [
                "hasBattery": session.hasInternalBattery,
                "threshold": settings.lowThresholdPercent
            ])
        }
    }

    private var previewStage: some View {
        SettingsIslandStage(
            options: [
                tipOption(
                    id: "charging",
                    title: L10n.MacBattery.previewCharging,
                    badge: L10n.MacBattery.previewChargingBadge,
                    symbol: "bolt.fill",
                    tint: SettingsChrome.primary
                ),
                tipOption(
                    id: "full",
                    title: L10n.MacBattery.previewFull,
                    badge: "100%",
                    symbol: "battery.100",
                    tint: SettingsChrome.secondary
                ),
                tipOption(
                    id: "low",
                    title: L10n.MacBattery.previewLow,
                    badge: "\(settings.lowThresholdPercent)%",
                    symbol: "battery.25",
                    tint: SettingsChrome.error
                ),
                tipOption(
                    id: "unplugged",
                    title: L10n.MacBattery.previewUnplug,
                    badge: "64%",
                    symbol: "battery.75",
                    tint: SettingsChrome.onSurfaceVariant
                )
            ],
            selection: $previewSelection
        ) { option in
            WidgetSamplePreview.content(for: "builtin.macBatteryTip.\(option.id)", compact: true)
        }
    }

    private func tipOption(
        id: String,
        title: String,
        badge: String,
        symbol: String,
        tint: Color
    ) -> SettingsIslandStageOption {
        SettingsIslandStageOption(
            id: id,
            title: title,
            badge: badge,
            symbol: symbol,
            tint: tint,
            maxIslandWidth: SettingsIslandPreviewWidth.tip,
            hugsContent: WidgetSamplePreview.tipPreviewHugsContent,
            bottomRadius: 18,
            outlineStyle: .panel,
            minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
            compactShell: true
        )
    }

    private var thresholdCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.MacBattery.lowThreshold)
                            .font(SettingsChrome.Font.rowTitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.MacBattery.lowThresholdSubtitle)
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
                    ForEach(MacBatterySettings.lowThresholdPresets, id: \.self) { percent in
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
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }
}
