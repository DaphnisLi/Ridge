import SwiftUI

/// 「已复制」提示设置：岛样张说明（总开关在小组件库）。
struct CopiedNoticeWidgetConfigSection: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    previewStage
                    SettingsCard {
                        Text(L10n.CopiedNotice.configBody)
                            .font(SettingsChrome.Font.body)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(SettingsChrome.Spacing.cardPadding)
                    }
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            AppLog.info("CopiedNotice", "配置页已显示")
        }
    }

    private var previewStage: some View {
        SettingsIslandStage(
            options: [
                SettingsIslandStageOption(
                    id: "copied",
                    title: L10n.CopiedNotice.widgetName,
                    badge: L10n.Shelf.previewStageCopiedBadge,
                    symbol: "doc.on.clipboard",
                    tint: SettingsChrome.secondary,
                    maxIslandWidth: 220,
                    hugsContent: true,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: 88,
                    compactShell: true
                )
            ],
            selection: .constant("copied")
        ) { _ in
            WidgetSamplePreview.content(for: "builtin.copiedNotice", compact: true)
        }
    }
}
