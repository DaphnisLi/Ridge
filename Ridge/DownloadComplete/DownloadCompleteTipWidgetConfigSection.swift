import SwiftUI

/// 浏览器下载设置：完成后点击动作 + 进行中/完成样张。
struct DownloadCompleteTipWidgetConfigSection: View {
    @ObservedObject private var settings = DownloadCompleteSettings.shared
    @ObservedObject private var session = DownloadCompleteSession.shared
    @State private var previewID = "downloading"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    clickActionCard
                    previewCard
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
                "pending": session.pending?.fileName ?? ""
            ])
        }
    }

    private var clickActionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.DownloadComplete.clickActionTitle)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.DownloadComplete.clickActionSubtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsSegmentedControl(
                    items: DownloadCompleteClickAction.allCases.map { action in
                        SettingsSegmentedControl.Item(
                            id: action.rawValue,
                            title: action == .openWithDefaultApp
                                ? L10n.DownloadComplete.openDefaultApp
                                : L10n.DownloadComplete.revealInFinder,
                            selected: settings.clickAction == action
                        ) {
                            settings.clickAction = action
                        }
                    }
                )
            }
            .padding(SettingsChrome.Spacing.cardPadding)
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
            ],
            selection: $previewID
        ) { option in
            Group {
                if option.id == "downloading" {
                    DownloadCompactStandbyView.previewSample(
                        fileName: "Archive.zip",
                        phase: .downloading,
                        speedBytesPerSecond: 2_400_000
                    )
                } else {
                    DownloadCompactStandbyView.previewSample(fileName: "Report.pdf")
                }
            }
            .frame(minHeight: SettingsIslandPreviewWidth.tipDetailMinHeight)
            .allowsHitTesting(false)
        }
    }
}
