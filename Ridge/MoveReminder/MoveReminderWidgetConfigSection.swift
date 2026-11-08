import SwiftUI

/// 久坐起身提醒设置：居中岛样张 + 触发 / 离开重置 / 联动活动时长 / 反馈免打扰。
struct MoveReminderWidgetConfigSection: View {
    @ObservedObject private var settings = MoveReminderSettings.shared
    @ObservedObject private var session = MoveReminderSession.shared

    private let amber = Color(red: 1.0, green: 0.584, blue: 0.0)
    /// 岛内左右统一边距（预览无 IslandChrome，需自行对称）。
    private let islandEdgeInset: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    islandPreviewStage
                    activeTriggerCard
                    leaveResetCard
                    restDurationCard
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

    // MARK: - 岛样张（随设置变；左右边距对称）

    private var islandPreviewStage: some View {
        MoveReminderNoticeCard.previewSample(
            activeMinutes: settings.activeTriggerMinutes,
            restMinutes: settings.suggestedRestMinutes
        )
        .padding(.horizontal, islandEdgeInset)
        .padding(.vertical, 12)
        .background(
            IslandPanelShape(bottomRadius: 24)
                .fill(Color(red: 0.118, green: 0.078, blue: 0.071))
                .overlay(
                    IslandPanelShape(bottomRadius: 24)
                        .stroke(amber.opacity(0.30), lineWidth: 1)
                )
                .shadow(color: amber.opacity(0.18), radius: 22, y: 10)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        )
        .clipShape(IslandPanelShape(bottomRadius: 24))
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 132)
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.surfaceContainer)
        )
        .allowsHitTesting(false)
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

    private var restDurationCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.MoveReminder.restTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.MoveReminder.restSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                SettingsSegmentedControl(
                    items: settings.restOptionsForActive.map { minutes in
                        SettingsSegmentedControl.Item(
                            id: "rest-\(settings.activeTriggerMinutes)-\(minutes)",
                            title: L10n.MoveReminder.minutes(minutes),
                            selected: settings.suggestedRestMinutes == minutes
                        ) {
                            settings.suggestedRestMinutes = minutes
                        }
                    }
                )
                .frame(maxWidth: 280)
                .id(settings.activeTriggerMinutes)
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
