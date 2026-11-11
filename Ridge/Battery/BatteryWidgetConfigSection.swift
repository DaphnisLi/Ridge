import SwiftUI

/// 「电量与外设」实况预览 + 排序 / 点击操作。
struct BatteryWidgetConfigSection: View {
    @ObservedObject private var session = BatterySession.shared
    @ObservedObject private var settings = BatterySettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    SettingsIslandPreviewCard(widgetID: "system.controlDeck.battery")

                    Text(L10n.Battery.sortPrioritySection)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .padding(.top, 2)

                    sortLogicCard
                    clickActionCard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreDeckDefaults()
                session.refresh(reason: "restoreDeckDefaults")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            session.start()
            session.refresh(reason: "batteryConfigAppear")
            AppLog.info("Battery", "电量实况配置页已显示", [
                "devices": session.devices.count,
                "sort": settings.peripheralSortMode.rawValue,
                "click": settings.peripheralClickAction.rawValue
            ])
        }
        .onChange(of: settings.peripheralSortMode) { _, _ in
            session.refresh(reason: "sortModeChanged")
        }
    }

    private var sortLogicCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Battery.sortLogicTitle)
                        .font(SettingsChrome.Font.rowTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Battery.sortLogicSubtitle)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSegmentedControl(
                    items: BatteryPeripheralSortMode.allCases.map { mode in
                        .init(
                            id: mode.rawValue,
                            title: sortTitle(mode),
                            selected: settings.peripheralSortMode == mode
                        ) {
                            settings.peripheralSortMode = mode
                        }
                    }
                )

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(SettingsChrome.Font.iconInline)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant.opacity(0.85))
                    Text(L10n.Battery.sortStrategyHint(settings.peripheralSortMode))
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
                )
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private var clickActionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Battery.clickActionTitle)
                        .font(SettingsChrome.Font.rowTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Battery.clickActionSubtitle)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSegmentedControl(
                    items: BatteryPeripheralClickAction.allCases.map { action in
                        .init(
                            id: action.rawValue,
                            title: clickTitle(action),
                            selected: settings.peripheralClickAction == action
                        ) {
                            settings.peripheralClickAction = action
                        }
                    }
                )
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private func sortTitle(_ mode: BatteryPeripheralSortMode) -> String {
        switch mode {
        case .recentActivity: return L10n.Battery.sortRecentActivity
        case .batteryLowToHigh: return L10n.Battery.sortBatteryLowToHigh
        case .connectionOrder: return L10n.Battery.sortConnectionOrder
        }
    }

    private func clickTitle(_ action: BatteryPeripheralClickAction) -> String {
        switch action {
        case .openBluetoothSettings: return L10n.Battery.clickOpenBluetooth
        case .refreshBatteryOnly: return L10n.Battery.clickRefreshOnly
        }
    }
}
