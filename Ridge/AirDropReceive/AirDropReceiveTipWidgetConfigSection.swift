import SwiftUI

/// 隔空投送接收 tip 设置：点击动作 + 样张预览。
struct AirDropReceiveTipWidgetConfigSection: View {
    @ObservedObject private var settings = AirDropReceiveSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    SettingsIslandPreviewCard(widgetID: AirDropReceiveTipWidget.manifest.id)

                    SettingsBentoCard {
                        SettingsBentoCardTitle(
                            symbol: "bolt.fill",
                            tint: SettingsChrome.primary,
                            title: L10n.AirDropReceive.clickActionTitle
                        )
                        Text(L10n.AirDropReceive.clickActionSubtitle)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        SettingsSegmentedControl(
                            items: [
                                SettingsSegmentedControl.Item(
                                    id: AirDropReceiveClickAction.openWithDefaultApp.rawValue,
                                    title: L10n.AirDropReceive.openWithDefaultApp,
                                    selected: settings.clickAction == .openWithDefaultApp,
                                    leadingSymbol: "arrow.up.right.square"
                                ) {
                                    settings.clickAction = .openWithDefaultApp
                                },
                                SettingsSegmentedControl.Item(
                                    id: AirDropReceiveClickAction.revealInFinder.rawValue,
                                    title: L10n.AirDropReceive.revealInFinder,
                                    selected: settings.clickAction == .revealInFinder,
                                    leadingSymbol: "folder"
                                ) {
                                    settings.clickAction = .revealInFinder
                                },
                            ]
                        )
                    }
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
            AirDropReceiveSession.shared.start()
            AppLog.info("AirDrop", "配置页已显示", [
                "action": settings.clickAction.rawValue
            ])
        }
    }
}
