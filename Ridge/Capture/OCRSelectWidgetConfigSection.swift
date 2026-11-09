import SwiftUI

/// 框选文字提取设置：样张预览 + 快捷键 / 剪贴板 / 触感音效。
struct OCRSelectWidgetConfigSection: View {
    @ObservedObject private var settings = OCRSelectSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    previewStage
                    optionsCard
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
            CaptureHotKeyCoordinator.shared.start()
            AppLog.warn("OCRSelect", "配置页已显示", [
                "chord": settings.hotKey.displayString,
                "saveToHistory": settings.saveToHistory
            ])
        }
    }

    private var previewStage: some View {
        SettingsIslandStage(
            title: nil,
            options: [
                SettingsIslandStageOption(
                    id: "guide",
                    title: L10n.OCRSelect.previewStageTitle,
                    badge: L10n.OCRSelect.previewStageBadge,
                    symbol: "text.viewfinder",
                    tint: SettingsChrome.primary,
                    maxIslandWidth: 480,
                    hugsContent: true,
                    bottomRadius: 18,
                    minStageHeight: 88,
                    compactShell: true
                )
            ],
            selection: .constant("guide")
        ) { _ in
            OCRSelectTipIslandView(compact: true, previewNotchWidth: 140)
                .environment(\.islandNotchWidth, 140)
                .environment(\.islandNotchHeight, 30)
        }
    }

    private var optionsCard: some View {
        SettingsCard {
            SettingsFormRows {
                SettingsHotKeyRecorder(
                    chord: $settings.hotKey,
                    title: L10n.OCRSelect.hotKeyTitle,
                    subtitle: L10n.OCRSelect.hotKeySubtitle
                )
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.vertical, 8)

                SettingsHairline()
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)

                SettingsSwitchRow(
                    title: L10n.OCRSelect.saveToHistoryTitle,
                    subtitle: L10n.OCRSelect.saveToHistorySubtitle,
                    isOn: $settings.saveToHistory
                )
            }
        }
    }
}
