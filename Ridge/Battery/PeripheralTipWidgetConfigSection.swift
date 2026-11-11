import SwiftUI

/// 外设提示设置：低电 / 满电 / 接入三档 + 岛上样张。
struct PeripheralTipWidgetConfigSection: View {
    @ObservedObject private var settings = BatterySettings.shared
    @State private var previewSelection = "low"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    previewStage
                    BatteryAlertOptionsCard()
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreTipDefaults()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            BatterySession.shared.start()
            AppLog.info("PeripheralTip", "配置页已显示", [
                "low": settings.lowAlertEnabled,
                "full": settings.fullChargeAlertEnabled,
                "connect": settings.connectAlertEnabled,
                "threshold": settings.lowThresholdPercent
            ])
        }
    }

    private var previewStage: some View {
        SettingsIslandStage(
            options: [
                SettingsIslandStageOption(
                    id: "low",
                    title: L10n.PeripheralTip.previewLow,
                    badge: "\(settings.lowThresholdPercent)%",
                    symbol: "battery.25",
                    tint: SettingsChrome.error,
                    maxIslandWidth: 420,
                    hugsContent: true,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: 88,
                    compactShell: true
                ),
                SettingsIslandStageOption(
                    id: "full",
                    title: L10n.PeripheralTip.previewFull,
                    badge: "100%",
                    symbol: "battery.100.bolt",
                    tint: SettingsChrome.secondary,
                    maxIslandWidth: 420,
                    hugsContent: true,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: 88,
                    compactShell: true
                ),
                SettingsIslandStageOption(
                    id: "connect",
                    title: L10n.PeripheralTip.previewConnect,
                    badge: L10n.PeripheralTip.previewConnectBadge,
                    symbol: "cable.connector",
                    tint: SettingsChrome.primary,
                    maxIslandWidth: 420,
                    hugsContent: true,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: 88,
                    compactShell: true
                )
            ],
            selection: $previewSelection
        ) { option in
            WidgetSamplePreview.content(for: "builtin.peripheralTip.\(option.id)", compact: true)
        }
    }

}
