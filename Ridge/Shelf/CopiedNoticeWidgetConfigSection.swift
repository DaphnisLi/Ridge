import SwiftUI

/// 「已复制」提示设置：岛样张 + 触感反馈（总开关在小组件库）。
struct CopiedNoticeWidgetConfigSection: View {
    @ObservedObject private var settings = CopiedNoticeSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    previewStage
                    SettingsCard {
                        SettingsSwitchRow(
                            title: L10n.CopiedNotice.hapticTitle,
                            subtitle: L10n.CopiedNotice.hapticSubtitle,
                            isOn: $settings.hapticEnabled
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
            AppLog.info("CopiedNotice", "配置页已显示", ["haptic": settings.hapticEnabled])
        }
    }

    private var previewStage: some View {
        SettingsIslandStage(
            options: [
                SettingsIslandStageOption(
                    id: "copied",
                    title: L10n.CopiedNotice.widgetName,
                    badge: L10n.Shelf.previewStageCopiedBadge,
                    symbol: "clipboard",
                    tint: SettingsChrome.secondary,
                    maxIslandWidth: 120,
                    hugsContent: true,
                    bottomRadius: IslandChrome.notchRightOrbDiameter / 2,
                    outlineStyle: .circle,
                    minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
                    compactShell: true,
                    scalesBlackIslandToLibrary: false
                )
            ],
            selection: .constant("copied")
        ) { _ in
            WidgetSamplePreview.content(for: "builtin.copiedNotice", compact: true)
        }
    }
}
