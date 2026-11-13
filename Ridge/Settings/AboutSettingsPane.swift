import AppKit
import SwiftUI

/// 关于：版本、法律、反馈、诊断。
struct AboutSettingsPane: View {
    @State private var includeDiagnosticsInFeedback = true
    @State private var statusHint: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                SettingsCard {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ridge")
                                .font(SettingsChrome.Font.sectionTitle)
                                .foregroundStyle(SettingsChrome.onSurface)
                            Text(L10n.About.versionFormat(AppIdentity.versionLabel))
                                .font(SettingsChrome.Font.monoValue)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            Text(AppIdentity.copyright)
                                .font(SettingsChrome.Font.caption)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(SettingsChrome.Spacing.cardPadding)
                }

                SettingsPaneSection(title: L10n.About.legalSection) {
                    aboutLinkRow(title: L10n.About.privacyPolicy) {
                        flash(LegalDocumentOpener.open(.privacy))
                    }
                    SettingsHairline()
                    aboutLinkRow(title: L10n.About.termsOfUse) {
                        flash(LegalDocumentOpener.open(.terms))
                    }
                }

                SettingsPaneSection(title: L10n.About.supportSection) {
                    SettingsSwitchRow(
                        title: L10n.About.attachDiagnostics,
                        subtitle: L10n.About.attachDiagnosticsSubtitle,
                        isOn: $includeDiagnosticsInFeedback
                    )
                    SettingsHairline()
                    aboutLinkRow(title: L10n.About.sendFeedback) {
                        flash(FeedbackService.openMail(includeDiagnostics: includeDiagnosticsInFeedback))
                    }
                    SettingsHairline()
                    aboutLinkRow(title: L10n.About.copyDiagnostics) {
                        flash(DiagnosticsExporter.copyToPasteboard(), okMessage: L10n.About.diagnosticsCopied)
                    }
                    SettingsHairline()
                    aboutLinkRow(title: L10n.About.checkForUpdates) {
                        UpdateService.shared.checkForUpdates(userInitiated: true)
                    }
                    SettingsHairline()
                    aboutLinkRow(title: L10n.About.openWebsite) {
                        flash(NSWorkspace.shared.open(AppIdentity.websiteURL))
                    }
                }

                if let statusHint, !statusHint.isEmpty {
                    Text(statusHint)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
            }
            .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
            .padding(.vertical, 20)
        }
        .onAppear {
            AppLog.warn("Settings", "关于页已显示", ["version": AppIdentity.versionLabel])
        }
    }

    private func aboutLinkRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(SettingsChrome.Font.rowTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(SettingsChrome.Font.iconInline)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func flash(_ ok: Bool, okMessage: String? = nil) {
        if ok {
            statusHint = okMessage
        } else {
            statusHint = L10n.About.actionFailed
        }
    }
}
