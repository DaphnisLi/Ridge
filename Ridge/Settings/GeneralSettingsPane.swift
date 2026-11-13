import SwiftUI

/// 通用：开机自启、检查更新。
struct GeneralSettingsPane: View {
    @ObservedObject private var loginItem = LoginItemService.shared
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                SettingsPaneSection(title: L10n.General.launchSection) {
                    SettingsSwitchRow(
                        title: L10n.General.launchAtLogin,
                        subtitle: L10n.General.launchAtLoginSubtitle,
                        isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { next in
                                let ok = loginItem.setEnabled(next)
                                if !ok {
                                    loginItem.openSystemLoginItemsSettings()
                                }
                            }
                        )
                    )
                    if let err = loginItem.lastError, !err.isEmpty {
                        Text(err)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.error)
                            .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                            .padding(.bottom, 8)
                    }
                    SettingsHairline()
                    Button {
                        loginItem.openSystemLoginItemsSettings()
                    } label: {
                        Text(L10n.General.openLoginItems)
                            .font(SettingsChrome.Font.body)
                            .foregroundStyle(SettingsChrome.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                    .padding(.vertical, 10)
                }

                SettingsPaneSection(title: L10n.General.updatesSection) {
                    SettingsSwitchRow(
                        title: L10n.General.autoCheckUpdates,
                        subtitle: L10n.General.autoCheckUpdatesSubtitle,
                        isOn: $updates.automaticallyChecks
                    )
                    SettingsHairline()
                    Button {
                        updates.checkForUpdates(userInitiated: true)
                    } label: {
                        HStack {
                            Text(L10n.General.checkForUpdatesNow)
                                .font(SettingsChrome.Font.body)
                                .foregroundStyle(SettingsChrome.primary)
                            Spacer()
                        }
                        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let msg = updates.lastMessage, !msg.isEmpty {
                        Text(msg)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                            .padding(.bottom, 10)
                    }
                }
            }
            .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
            .padding(.vertical, 20)
        }
        .onAppear {
            loginItem.refresh()
            AppLog.warn("Settings", "通用设置页已显示", ["loginItem": loginItem.isEnabled])
        }
    }
}
