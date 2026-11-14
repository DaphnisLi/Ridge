import SwiftUI

/// 库卡 / 引导推荐卡：把唤醒快捷键做成胶囊标注，避免淹没在副文案里。
struct CaptureHotKeySummaryLabel: View {
    enum Kind {
        case colorPick
        case ocrSelect
    }

    let kind: Kind
    let chord: String

    private var prefix: String {
        switch kind {
        case .colorPick: return L10n.ColorPick.librarySummaryPrefix
        case .ocrSelect: return L10n.OCRSelect.librarySummaryPrefix
        }
    }

    private var trailing: String {
        switch kind {
        case .colorPick: return L10n.ColorPick.librarySummaryTrailing
        case .ocrSelect: return L10n.OCRSelect.librarySummaryTrailing
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(prefix)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            Text(chord)
                .font(SettingsChrome.Font.monoEmphasis)
                .foregroundStyle(SettingsChrome.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                        .fill(SettingsChrome.primary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                        .strokeBorder(SettingsChrome.primary.opacity(0.28), lineWidth: 1)
                )
            Text("· \(trailing)")
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(prefix)\(chord) · \(trailing)")
    }
}
