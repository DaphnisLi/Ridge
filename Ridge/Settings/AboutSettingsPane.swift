import AppKit
import SwiftUI

/// 关于与支持：品牌、更新、法律、反馈（对齐设置稿面结构）。
struct AboutSettingsPane: View {
    @ObservedObject private var updates = UpdateService.shared
    @State private var statusHint: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                heroCard
                legalSection
                supportSection
                if let statusHint, !statusHint.isEmpty {
                    Text(statusHint)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
            }
            .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            AppLog.warn("Settings", "关于页已显示", ["version": AppIdentity.versionLabel])
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ridge")
                        .font(SettingsChrome.Font.heroMetric)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.About.tagline)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
                Spacer(minLength: 0)
            }

            SettingsHairline.flush

            HStack(alignment: .center, spacing: 12) {
                Toggle("", isOn: $updates.automaticallyChecks)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.About.autoCheckUpdates)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.About.autoCheckUpdates)
                        .font(SettingsChrome.Font.rowTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.About.autoCheckUpdatesSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }

                Spacer(minLength: 12)

                HStack(alignment: .center, spacing: 12) {
                    if let msg = updates.lastMessage, !msg.isEmpty {
                        statusChip(msg)
                    } else {
                        statusChip(L10n.About.upToDateStatus(AppIdentity.versionLabel))
                    }
                    Button {
                        updates.checkForUpdates(userInitiated: true)
                        AppLog.warn("Settings", "关于页检查更新")
                    } label: {
                        Label(L10n.About.checkForUpdatesButton, systemImage: "arrow.triangle.2.circlepath")
                            .font(SettingsChrome.Font.rowTitle)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(SettingsChrome.primary)
                }
            }
        }
        .padding(SettingsChrome.Spacing.cardPadding)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                    .fill(SettingsChrome.cardBackground)
                Circle()
                    .fill(SettingsChrome.primary.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .blur(radius: 28)
                    .offset(x: 40, y: -48)
                    .allowsHitTesting(false)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
    }

    private func statusChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(SettingsChrome.secondary)
                .frame(width: 6, height: 6)
            Text(text)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(symbol: "checkmark.shield", title: L10n.About.legalSection)
            SettingsCard {
                VStack(spacing: 0) {
                    legalRow(
                        symbol: "doc.text.magnifyingglass",
                        tint: SettingsChrome.primary,
                        title: L10n.About.privacyPolicy,
                        subtitle: L10n.About.privacyPolicySubtitle
                    ) {
                        flash(LegalDocumentOpener.open(.privacy))
                    }
                    SettingsHairline()
                    legalRow(
                        symbol: "scalemass",
                        tint: Color(red: 0.30, green: 0.29, blue: 0.79),
                        title: L10n.About.termsOfUse,
                        subtitle: L10n.About.termsOfUseSubtitle
                    ) {
                        flash(LegalDocumentOpener.open(.terms))
                    }
                }
            }
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(symbol: "terminal", title: L10n.About.supportSection)
            SettingsCard {
                HStack(spacing: 10) {
                    supportTile(
                        symbol: "lightbulb",
                        tint: SettingsChrome.primary,
                        title: L10n.About.sendSuggestion,
                        subtitle: L10n.About.sendSuggestionSubtitle
                    ) {
                        flash(FeedbackService.openMail(kind: .suggestion))
                    }
                    supportTile(
                        symbol: "ant",
                        tint: SettingsChrome.error,
                        title: L10n.About.reportBug,
                        subtitle: L10n.About.reportBugSubtitle
                    ) {
                        flash(FeedbackService.openMail(kind: .bugReport))
                    }
                }
                .padding(SettingsChrome.Spacing.cardPadding)
            }
        }
    }

    // MARK: - Pieces

    private func sectionLabel(symbol: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(SettingsChrome.Font.iconInline)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            Text(title)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 4)
    }

    private func legalRow(
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(SettingsChrome.Font.iconTile)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(subtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
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

    private func supportTile(
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(SettingsChrome.Font.iconTile)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SettingsChrome.cardBackground)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SettingsChrome.Font.label)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(subtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(SettingsChrome.Font.iconInline)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.surfaceContainer)
            )
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
