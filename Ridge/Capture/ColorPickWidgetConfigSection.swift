import SwiftUI

/// 取色设置：样张预览 + 快捷键 / 自动复制十六进制。
struct ColorPickWidgetConfigSection: View {
    @ObservedObject private var settings = ColorPickSettings.shared

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
            AppLog.warn("ColorPick", "配置页已显示", [
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
                    title: L10n.Shelf.previewStageColorPick,
                    badge: L10n.Shelf.previewStageColorPickBadge,
                    symbol: "eyedropper",
                    tint: SettingsChrome.primary,
                    maxIslandWidth: 360,
                    hugsContent: true,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: 88,
                    compactShell: true
                )
            ],
            selection: .constant("guide")
        ) { _ in
            // 与久坐 tip 同款：预览壳无 IslandChrome，舞台只补左右/底。
            ColorPickTipIslandView(compact: true)
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: 34)
        }
    }

    private var optionsCard: some View {
        SettingsCard {
            SettingsFormRows {
                SettingsHotKeyRecorder(
                    chord: $settings.hotKey,
                    title: L10n.ColorPick.hotKeyTitle,
                    subtitle: L10n.ColorPick.hotKeySubtitle
                )
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.vertical, 8)

                SettingsHairline()
                    .padding(.horizontal, SettingsChrome.Spacing.cardPadding)

                SettingsSwitchRow(
                    title: L10n.ColorPick.saveToHistoryTitle,
                    subtitle: L10n.ColorPick.saveToHistorySubtitle,
                    isOn: $settings.saveToHistory
                )
            }
        }
    }
}
