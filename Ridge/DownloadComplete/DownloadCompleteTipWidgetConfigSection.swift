import SwiftUI

/// 浏览器下载设置：完成后快速动作 + 进行中/完成样张。
struct DownloadCompleteTipWidgetConfigSection: View {
    @ObservedObject private var settings = DownloadCompleteSettings.shared
    @ObservedObject private var session = DownloadCompleteSession.shared
    @State private var previewID = "downloading"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    previewCard
                    quickActionsCard
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
            DownloadCompleteSession.shared.start()
            AppLog.info("Download", "配置页已显示", [
                "action": settings.clickAction.rawValue,
                "shortcut": settings.keyboardShortcutEnabled,
                "chord": settings.hotKey.displayString,
                "pending": session.pending?.fileName ?? ""
            ])
        }
    }

    private var quickActionsCard: some View {
        SettingsBentoCard {
            SettingsBentoCardTitle(
                symbol: "bolt.fill",
                tint: SettingsChrome.primary,
                title: L10n.DownloadComplete.quickActionsTitle
            )

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.DownloadComplete.clickActionTitle)
                        .font(SettingsChrome.Font.rowTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.DownloadComplete.clickActionSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SettingsSegmentedControl(
                    items: [
                        SettingsSegmentedControl.Item(
                            id: DownloadCompleteClickAction.openWithDefaultApp.rawValue,
                            title: L10n.DownloadComplete.openDefaultApp,
                            selected: settings.clickAction == .openWithDefaultApp,
                            leadingSymbol: "arrow.up.right.square"
                        ) {
                            settings.clickAction = .openWithDefaultApp
                        },
                        SettingsSegmentedControl.Item(
                            id: DownloadCompleteClickAction.revealInFinder.rawValue,
                            title: L10n.DownloadComplete.revealInFinder,
                            selected: settings.clickAction == .revealInFinder,
                            leadingSymbol: "folder"
                        ) {
                            settings.clickAction = .revealInFinder
                        },
                    ]
                )
                .frame(maxWidth: 320)
            }

            SettingsHairline.flush

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.DownloadComplete.shortcutTitle)
                        .font(SettingsChrome.Font.rowTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.DownloadComplete.shortcutSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $settings.keyboardShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.DownloadComplete.shortcutTitle)
            }

            SettingsHotKeyRecorder(
                chord: $settings.hotKey,
                owner: .downloadComplete,
                title: L10n.DownloadComplete.shortcutChordTitle,
                subtitle: L10n.DownloadComplete.shortcutChordSubtitle
            )
            .disabled(!settings.keyboardShortcutEnabled)
            .opacity(settings.keyboardShortcutEnabled ? 1 : 0.45)
        }
    }

    private var previewCard: some View {
        SettingsIslandStage(
            options: [
                SettingsIslandStageOption(
                    id: "downloading",
                    title: L10n.DownloadComplete.downloadingBadge,
                    badge: L10n.DownloadComplete.downloadingBadge,
                    symbol: "arrow.down.circle.fill",
                    tint: SettingsChrome.primary,
                    maxIslandWidth: SettingsIslandPreviewWidth.tip,
                    minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
                    compactShell: true
                ),
                SettingsIslandStageOption(
                    id: "completed",
                    title: L10n.DownloadComplete.doneBadge,
                    badge: L10n.DownloadComplete.doneBadge,
                    symbol: "checkmark.circle.fill",
                    tint: SettingsChrome.secondary,
                    maxIslandWidth: SettingsIslandPreviewWidth.tip,
                    minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
                    compactShell: true
                ),
                SettingsIslandStageOption(
                    id: "peninsula",
                    title: L10n.DownloadComplete.peninsulaPreviewStage,
                    badge: L10n.DownloadComplete.peninsulaPreviewStage,
                    symbol: "rectangle.righthalf.inset.filled",
                    tint: SettingsChrome.primary,
                    maxIslandWidth: SettingsIslandPreviewWidth.tip,
                    minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
                    compactShell: true
                ),
            ],
            selection: $previewID
        ) { option in
            Group {
                if option.id == "downloading" {
                    DownloadCompactStandbyView.previewSample(
                        fileName: "Docker.raw",
                        phase: .downloading,
                        speedBytesPerSecond: 41_000_000,
                        progressFraction: 0.82
                    )
                } else if option.id == "peninsula" {
                    DownloadCompactStandbyView.previewSample(
                        fileName: "Docker.raw",
                        phase: .downloading,
                        speedBytesPerSecond: 41_000_000,
                        progressFraction: 0.82,
                        flushSide: .trailing
                    )
                } else {
                    DownloadCompactStandbyView.previewSample(
                        fileName: "Docker.raw",
                        phase: .completed
                    )
                }
            }
            .frame(minHeight: SettingsIslandPreviewWidth.tipDetailMinHeight)
            .allowsHitTesting(false)
        }
    }
}
