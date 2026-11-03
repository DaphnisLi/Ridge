import SwiftUI

// MARK: - 卡片

/// 标准白底设置卡（圆角 12）。表单块、说明块统一用这个；禁止另铺灰渐变当卡底。
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                    .fill(SettingsChrome.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                            .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                    )
            )
    }
}

/// Bento / 模块卡（圆角 16、轻阴影）。灵动岛设置等模块化布局用。
struct SettingsBentoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.Spacing.cardInner) {
            content
        }
        .padding(SettingsChrome.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: SettingsChrome.cardStrokeWidth)
                )
                .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
        )
    }
}

/// 带分区标题的卡。
struct SettingsPaneSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SettingsChrome.Font.sectionTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            SettingsCard { content }
        }
    }
}

// MARK: - 表单行

struct SettingsFormRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
    }
}

struct SettingsGroupedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        SettingsFormRows { content }
    }
}

/// 左文案 + 右开关。
struct SettingsSwitchRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsChrome.Font.rowTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
        .padding(.vertical, 8)
    }
}

/// Bento 卡内带图标的小标题行。
struct SettingsBentoCardTitle: View {
    let symbol: String
    let tint: Color
    let title: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: symbol)
                    .font(SettingsChrome.Font.iconInline)
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(SettingsChrome.Font.cardTitle)
                .foregroundStyle(SettingsChrome.onSurface)

            if let badge {
                Text(badge)
                    .font(SettingsChrome.Font.micro)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
            }
        }
    }
}

/// 连续滑条：无刻度点；按 step 吸附。
struct SettingsSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let leading: String
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(SettingsChrome.Font.monoValue)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainerLow)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(SettingsChrome.outline.opacity(0.55), lineWidth: 1)
                            )
                    )
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { next in
                        let snapped = (next / step).rounded() * step
                        value = min(max(snapped, range.lowerBound), range.upperBound)
                    }
                ),
                in: range
            )
            HStack {
                Text(leading)
                Spacer(minLength: 0)
                Text(trailing)
            }
            .font(SettingsChrome.Font.footnote)
            .foregroundStyle(SettingsChrome.onSurfaceVariant)
        }
    }
}

/// 浅底分段选择条（几何预设 / 速度 / 震感等）。页内禁止再抄一套 pill 分段。
struct SettingsSegmentedControl: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let selected: Bool
        /// `false` 时仅作状态展示（如「自定义」指示），不可点。
        var isInteractive: Bool = true
        let action: () -> Void

        init(
            id: String,
            title: String,
            selected: Bool,
            isInteractive: Bool = true,
            action: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.selected = selected
            self.isInteractive = isInteractive
            self.action = action
        }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                let label = Text(item.title)
                    .font(item.selected ? SettingsChrome.Font.chipSelected : SettingsChrome.Font.chip)
                    .foregroundStyle(item.selected ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                            .fill(item.selected ? Color.white : Color.clear)
                            .shadow(color: item.selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                    )

                if item.isInteractive {
                    Button(action: item.action) { label }
                        .buttonStyle(.plain)
                } else {
                    label
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainer.opacity(0.7))
        )
    }
}

/// 卡内细分割线。
struct SettingsHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.05))
            .frame(height: 1)
    }
}
