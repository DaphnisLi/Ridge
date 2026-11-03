import AppKit
import SwiftUI

/// 设置页「岛预览」外包卡：白底 SettingsCard + 假数据岛；库卡 / 详情页统一用这个。
struct SettingsIslandPreviewCard: View {
    let widgetID: WidgetID
    var compact: Bool = false

    var body: some View {
        SettingsCard {
            WidgetSamplePreview.island(for: widgetID, compact: compact)
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.vertical, compact ? 16 : 22)
                .frame(maxWidth: .infinity)
        }
    }
}

/// 设置页岛预览壳（上直角、下圆角）。新预览请调 `WidgetSamplePreview.island`，勿单独再包壳。
struct WidgetIslandPreviewShell<Content: View>: View {
    var compact: Bool = false
    var bottomRadius: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    private var radius: CGFloat {
        bottomRadius ?? (compact ? 16 : 26)
    }

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: radius)
        content()
            .frame(maxWidth: .infinity)
            .background(
                shape
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        shape.stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(compact ? 0.22 : 0.35), radius: compact ? 12 : 24, y: compact ? 6 : 12)
            )
            .clipShape(shape)
    }
}

/// 设置页小组件预览的**唯一入口**（假数据）。库卡 `compact: true`，详情页 `compact: false`。
/// 新 widget：在 `content(for:compact:)` 加 case，调用方只调 `island(for:compact:)`。
@MainActor
enum WidgetSamplePreview {
    /// 统一预览组件：壳 + 假数据内容。
    @ViewBuilder
    static func island(for id: WidgetID, compact: Bool) -> some View {
        WidgetIslandPreviewShell(compact: compact) {
            content(for: id, compact: compact)
        }
    }

    @ViewBuilder
    static func content(for id: WidgetID, compact: Bool) -> some View {
        switch id {
        case "builtin.meeting":
            meetingSample(compact: compact)
        case "builtin.media":
            mediaSample(compact: compact)
        case "system.controlDeck.battery":
            batterySample(compact: compact)
        case "system.controlDeck.volume":
            deckModuleSample(
                symbol: "speaker.wave.2.fill",
                title: L10n.ControlDeck.moduleVolume,
                rows: [
                    (L10n.Sound.masterOutputVolume, "62%"),
                    (L10n.Sound.currentOutputDevice, "MacBook Pro Speakers")
                ],
                compact: compact
            )
        case "system.controlDeck.projects":
            deckModuleSample(
                symbol: "hammer.fill",
                title: L10n.ControlDeck.moduleProjects,
                rows: [
                    (L10n.ControlDeck.moduleProjects, "Ridge"),
                    (L10n.Projects.rootsTitle, "~/project/Ridge")
                ],
                compact: compact
            )
        case "system.controlDeck.shelf":
            deckModuleSample(
                symbol: "tray.full.fill",
                title: L10n.ControlDeck.moduleShelf,
                rows: [
                    (L10n.Shelf.clipboardImagePreview, "12:41"),
                    ("https://example.com", "12:38")
                ],
                compact: compact
            )
        default:
            genericSample(
                title: WidgetRegistry.shared.manifest(for: id)?.displayName ?? id,
                symbol: "rectangle.3.group",
                compact: compact
            )
        }
    }

    private static func meetingSample(compact: Bool) -> some View {
        let lead = max(MeetingSettings.shared.leadMinutes, 1)
        return MeetingIslandCardView.previewSample(leadMinutes: lead)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 8 : 14)
            .frame(maxWidth: compact ? .infinity : 540)
            .frame(minHeight: compact ? 64 : nil)
    }

    private static func mediaSample(compact: Bool) -> some View {
        MediaIslandCardView.previewSample()
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 8 : 14)
            .frame(maxWidth: compact ? .infinity : 540)
            .frame(minHeight: compact ? 64 : 148)
    }

    private static func batterySample(compact: Bool) -> some View {
        BatteryDeckView(previewDevices: BatteryDeckView.sampleDevices)
            .frame(height: compact ? 96 : 168)
            .padding(.horizontal, compact ? 6 : 0)
            .padding(.vertical, compact ? 6 : 10)
    }

    private static func deckModuleSample(
        symbol: String,
        title: String,
        rows: [(String, String)],
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ForEach(Array(rows.prefix(compact ? 1 : rows.count).enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, compact ? 6 : 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func genericSample(title: String, symbol: String, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .frame(height: compact ? 44 : 56)
        .frame(maxWidth: .infinity)
    }
}
