import AppKit
import SwiftUI

/// 货架模块预览配置；「已复制」为下方独立开关 + 预览。
struct ShelfWidgetConfigSection: View {
    @ObservedObject private var shelfSettings = ShelfSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsIslandPreviewCard(
                widgetID: ControlDeckSettings.pageIDPrefix + ".shelf"
            )

            copiedNoticeSection
        }
        .onAppear {
            AppLog.debug("ControlDeck", "货架配置预览已显示")
        }
    }

    private var copiedNoticeSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsIslandStage(compact: true, maxIslandWidth: 148) {
                    ClipboardCopiedIslandView(compact: true)
                }

                SettingsSwitchRow(
                    title: L10n.Shelf.copiedNoticeToggle,
                    subtitle: L10n.Shelf.copiedNoticeToggleSubtitle,
                    isOn: $shelfSettings.showCopiedNotice
                )
            }
            .padding(.top, 12)
        }
    }
}

/// 混音台模块预览配置。
struct VolumeWidgetConfigSection: View {
    @ObservedObject private var soundSettings = SoundSettings.shared
    @ObservedObject private var sound = SoundSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 未授权置顶；已授权整卡不展示。
            SettingsPermissionCard(
                status: sound.tapAvailability == .needsScreenCapture ? .request : .authorized,
                symbol: "rectangle.dashed.badge.record",
                tint: SettingsChrome.primary,
                title: L10n.Sound.screenCaptureAccess,
                subtitle: L10n.Sound.screenCaptureAccessDesc,
                requestTitle: L10n.Sound.screenCaptureAllow,
                requestSymbol: "rectangle.dashed.badge.record",
                action: { sound.requestScreenCaptureAccess() }
            )
            previewChrome(moduleID: "volume")
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Sound.mixerPrefsTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    Text(L10n.Sound.mixerPrefsIntro)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                    SettingsSwitchRow(
                        title: L10n.Sound.rememberVolumes,
                        isOn: $soundSettings.rememberVolumes
                    )
                    HStack(spacing: 10) {
                        Button(L10n.Sound.resetAppVolumes) {
                            sound.resetAppVolumes()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            sound.start()
            AppLog.debug("ControlDeck", "混音台配置预览已显示")
        }
    }
}

/// 项目释放模块预览配置。
struct ProjectsWidgetConfigSection: View {
    @ObservedObject private var projectSettings = ProjectSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            previewChrome(moduleID: "projects")
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.Projects.rootsTitle)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 0)
                        Button(L10n.Projects.addRoot) {
                            pickProjectRoot()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    Text(L10n.Projects.rootsIntro)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 0) {
                        if projectSettings.roots.isEmpty {
                            Text(L10n.Projects.rootsEmpty)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            ForEach(projectSettings.roots, id: \.self) { root in
                                HStack {
                                    Text(root)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Button {
                                        projectSettings.removeRoot(root)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                if root != projectSettings.roots.last {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
                    )
                    .padding(16)
                }
            }
        }
        .onAppear {
            AppLog.debug("ControlDeck", "项目释放配置预览已显示")
        }
    }

    private func pickProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.Projects.addRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectSettings.addRoot(url.path)
        AppLog.info("Projects", "设置页添加项目根目录")
    }
}

// MARK: - Shared chrome

@MainActor
@ViewBuilder
private func previewChrome(moduleID: String) -> some View {
    SettingsIslandPreviewCard(widgetID: ControlDeckSettings.pageIDPrefix + "." + moduleID)
}
