import SwiftUI

/// 久坐起身提醒设置：岛样张 + 触发 / 离开重置 / 反馈免打扰。
struct MoveReminderWidgetConfigSection: View {
    @ObservedObject private var settings = MoveReminderSettings.shared
    @ObservedObject private var session = MoveReminderSession.shared

    private let amber = Color(red: 1.0, green: 0.584, blue: 0.0)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    islandPreviewStage
                    activeTriggerCard
                    leaveResetCard
                    feedbackCard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, SettingsChrome.Spacing.pageHorizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreDefaults()
            }
        }
        .background(SettingsChrome.pageBackground)
        .onAppear {
            session.start()
            AppLog.info("MoveReminder", "配置页已显示", [
                "active": settings.activeTriggerMinutes,
                "leave": settings.leaveResetMinutes,
                "rest": settings.suggestedRestMinutes
            ])
        }
    }

    // MARK: - 岛样张（上直角下圆角，与真岛一致）

    private var islandPreviewStage: some View {
        SettingsIslandStage(
            options: [
                SettingsIslandStageOption(
                    id: "move",
                    title: L10n.MoveReminder.widgetName,
                    badge: "\(settings.activeTriggerMinutes)m",
                    symbol: "figure.seated.side.right",
                    tint: amber,
                    maxIslandWidth: SettingsIslandPreviewWidth.tip,
                    hugsContent: WidgetSamplePreview.tipPreviewHugsContent,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: 88,
                    compactShell: true
                )
            ],
            selection: .constant("move")
        ) { _ in
            // 与会议 tip 同款：预览壳无 IslandChrome，舞台只补左右/底。
            MoveReminderNoticeCard.previewSample(
                activeMinutes: settings.activeTriggerMinutes,
                restMinutes: settings.suggestedRestMinutes,
                compact: true
            )
            .padding(.horizontal, IslandChrome.contentHorizontal)
            .padding(.bottom, IslandChrome.compactTipBottom)
            .frame(minHeight: 34)
            .id("\(settings.activeTriggerMinutes)-\(settings.suggestedRestMinutes)")
        }
    }

    // MARK: - Cards

    private var activeTriggerCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.MoveReminder.activeTriggerTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.MoveReminder.activeTriggerSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsSegmentedControl(
                    items: MoveReminderSettings.activeOptions.map { minutes in
                        SettingsSegmentedControl.Item(
                            id: "active-\(minutes)",
                            title: L10n.MoveReminder.minutes(minutes),
                            selected: settings.activeTriggerMinutes == minutes
                        ) {
                            settings.activeTriggerMinutes = minutes
                        }
                    }
                )
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private var leaveResetCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.MoveReminder.leaveResetTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.MoveReminder.leaveResetSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 与上方「连续活跃」同款分段条：字号、高度一致。
                SettingsSegmentedControl(
                    items: MoveReminderSettings.leaveOptions.map { minutes in
                        SettingsSegmentedControl.Item(
                            id: "leave-\(minutes)",
                            title: L10n.MoveReminder.minutes(minutes),
                            selected: settings.leaveResetMinutes == minutes
                        ) {
                            settings.leaveResetMinutes = minutes
                        }
                    }
                )
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private var feedbackCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.MoveReminder.feedbackSection)
                    .font(SettingsChrome.Font.sectionTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                    .padding(.top, SettingsChrome.Spacing.cardPadding)
                    .padding(.bottom, 4)

                SettingsSwitchRow(
                    title: L10n.MoveReminder.hapticTitle,
                    subtitle: L10n.MoveReminder.hapticSubtitle,
                    isOn: $settings.hapticEnabled
                )
                SettingsHairline()
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                SettingsSwitchRow(
                    title: L10n.MoveReminder.smartAvoidTitle,
                    subtitle: L10n.MoveReminder.smartAvoidSubtitle,
                    isOn: $settings.smartAvoidEnabled
                )
                .padding(.bottom, 8)
            }
        }
    }
}
