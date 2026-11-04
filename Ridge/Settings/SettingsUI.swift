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
                segment(item)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsChrome.surfaceContainer.opacity(0.7))
        )
    }

    @ViewBuilder
    private func segment(_ item: Item) -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
        let label = Text(item.title)
            .font(item.selected ? SettingsChrome.Font.chipSelected : SettingsChrome.Font.chip)
            .foregroundStyle(item.selected ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(
                shape
                    .fill(item.selected ? Color.white : Color.clear)
                    .shadow(color: item.selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
            )
            // plain Button 默认只点文字；整块长方形都要可点。
            .contentShape(shape)

        if item.isInteractive {
            Button(action: item.action) { label }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
        } else {
            label
                .frame(maxWidth: .infinity)
        }
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

/// 「恢复默认设置」公共按钮。样式以灵动岛设置页为准：`bordered` + 逆时针图标。
/// 各配置页只传 `action`，禁止再抄一套 plain 灰字链接。
struct SettingsRestoreDefaultsButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.Common.restoreDefaults, systemImage: "arrow.counterclockwise")
                .font(SettingsChrome.Font.label)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

/// 贴底固定的「恢复默认设置」栏：滚动区在上、本栏在下，滑动时位置不变（灵动岛设置页同款）。
struct SettingsRestoreDefaultsFooter: View {
    var action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            SettingsRestoreDefaultsButton(action: action)
        }
        .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
        .padding(.vertical, 12)
        .background(SettingsChrome.pageBackground.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }
}

/// 未授权权限卡（白底 + 图标 + 标题说明 + 右侧操作）。
/// **已授权时整卡不渲染**——用户侧只会出现「未授权」态，禁止再造「已授权」徽章或页内第二套授权 UI。
struct SettingsPermissionCard: View {
    enum Status: Equatable {
        case authorized
        case request
        case openSettings
        case busy
    }

    var status: Status
    let symbol: String
    var tint: Color = SettingsChrome.secondary
    let title: String
    let subtitle: String
    var requestTitle: String = L10n.Common.authorize
    var requestSymbol: String = "hand.raised.fill"
    var openSettingsTitle: String = L10n.Common.openSystemSettings
    var openSettingsSymbol: String = "gearshape"
    var busyTitle: String = L10n.Common.requesting
    var action: (() -> Void)? = nil

    var body: some View {
        if status != .authorized {
            SettingsCard {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.15))
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SettingsChrome.Font.rowTitle.weight(.semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(subtitle)
                            .font(SettingsChrome.Font.body)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    trailingAction
                }
                .padding(SettingsChrome.Spacing.cardPadding)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)。\(subtitle)")
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch status {
        case .authorized:
            EmptyView()
        case .request:
            Button {
                action?()
            } label: {
                actionChip(
                    title: requestTitle,
                    symbol: requestSymbol,
                    foreground: SettingsChrome.primary,
                    background: SettingsChrome.primary.opacity(0.12)
                )
            }
            .buttonStyle(.plain)
            .help(requestTitle)
        case .openSettings:
            Button {
                action?()
            } label: {
                actionChip(
                    title: openSettingsTitle,
                    symbol: openSettingsSymbol,
                    foreground: SettingsChrome.onSurface,
                    background: SettingsChrome.surfaceContainer
                )
            }
            .buttonStyle(.plain)
            .help(openSettingsTitle)
        case .busy:
            actionChip(
                title: busyTitle,
                symbol: nil,
                foreground: SettingsChrome.onSurfaceVariant,
                background: SettingsChrome.surfaceContainer,
                showsProgress: true
            )
        }
    }

    private func actionChip(
        title: String,
        symbol: String?,
        foreground: Color,
        background: Color,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(SettingsChrome.Font.iconInline)
            }
            Text(title)
                .font(SettingsChrome.Font.label)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                .fill(background)
        )
    }
}
