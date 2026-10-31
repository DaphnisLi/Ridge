import SwiftUI

struct IslandSettingsPane: View {
    @ObservedObject var settings: IslandSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appearanceRows
                SettingsCard { interactionRows }

                HStack {
                    Spacer(minLength: 0)
                    Button("恢复默认设置") {
                        settings.restoreDefaults()
                        AppLog.info("Settings", "已恢复默认设置")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            // 左右与窗口边界留白；滑条在卡片内拉满，不再额外缩一截。
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            // 设置窗级会话钉住展开；切到「小组件」页时不要在这里收起。
            IslandController.shared?.beginSettingsSession()
            AppLog.debug("Settings", "灵动岛设置页已显示")
        }
        .onChange(of: settings.animationSpeed) { _, value in
            AppLog.info("Settings", "动画速度已更新", ["speed": value])
        }
        .onChange(of: settings.hideInFullscreen) { _, value in
            AppLog.info("Settings", "全屏禁用岛", ["enabled": value])
        }
        .onChange(of: settings.hapticIntensity) { _, value in
            AppLog.info("Settings", "震感强度", ["level": value.rawValue])
            IslandHaptics.play(value)
        }
        .onChange(of: settings.bottomCornerRadius) { _, value in
            AppLog.info("Settings", "下圆角已更新", ["radius": value])
        }
        .onChange(of: settings.expandedWidth) { _, value in
            AppLog.info("Settings", "展开宽度", ["width": value])
        }
        .onChange(of: settings.theme) { _, value in
            AppLog.info("Settings", "预设主题", ["theme": value.rawValue])
        }
    }

    // MARK: - 外观

    @ViewBuilder
    private var appearanceRows: some View {
        // 预设主题单独成块，不用外层灰框（芯片自身已有灰底）。
        VStack(alignment: .leading, spacing: 10) {
            Text("预设主题")
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(IslandTheme.allCases) { theme in
                    IslandThemeChip(
                        theme: theme,
                        selected: settings.theme == theme
                    ) {
                        settings.theme = theme
                    }
                }
            }
        }

        // 宽度 / 圆角：同一灰框，中间横线分隔。
        SettingsCard {
            SettingsFormRows {
                SettingsLabeledSliderRow(
                    title: "展开后宽度",
                    value: $settings.expandedWidth,
                    range: IslandSettings.expandedWidthRange,
                    step: 10,
                    leadingHint: "窄",
                    trailingHint: "宽",
                    valueText: "\(Int(settings.expandedWidth.rounded())) pt"
                )

                Divider()
                    .padding(.leading, 16)

                SettingsLabeledSliderRow(
                    title: "下圆角",
                    value: $settings.bottomCornerRadius,
                    range: 0...36,
                    step: 1,
                    leadingHint: "直角",
                    trailingHint: "圆润",
                    valueText: "\(Int(settings.bottomCornerRadius.rounded())) pt"
                )
            }
        }
    }

    // MARK: - 交互

    @ViewBuilder
    private var interactionRows: some View {
        SettingsFormRows {
            SettingsLabeledSliderRow(
                title: "展开动画速度",
                value: $settings.animationSpeed,
                range: 0.5...2.0,
                step: 0.1,
                leadingHint: "慢",
                trailingHint: "快",
                valueText: String(format: "%.1f×", settings.animationSpeed)
            )

            Divider()
                .padding(.leading, 16)

            SettingsDiscreteSliderRow(
                title: "震感强度",
                selection: hapticIntensityBinding,
                labels: IslandHapticIntensity.allCases.map(\.title)
            )

            Divider()
                .padding(.leading, 16)

            SettingsSwitchRow(
                title: "全屏时禁用灵动岛",
                isOn: $settings.hideInFullscreen
            )
        }
    }

    private var hapticIntensityBinding: Binding<Int> {
        Binding(
            get: { settings.hapticIntensity.rawValue },
            set: { raw in
                settings.hapticIntensity = IslandHapticIntensity(rawValue: raw) ?? .medium
            }
        )
    }
}

// MARK: - 布局组件（仿系统触控板设置）

struct SettingsPaneSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            SettingsCard { content }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsChrome.cardBackground)
            )
    }
}

/// 表单行容器：白/灰底卡片内堆叠，行间无描边框。
struct SettingsFormRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
    }
}

/// 分组行兼容旧调用。
struct SettingsGroupedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        SettingsFormRows { content }
    }
}

/// 标签靠左 + 右侧滑条 + 下方刻度文案（仿「追踪速度 / 点按」）。
private struct SettingsLabeledSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let leadingHint: String
    let trailingHint: String
    let valueText: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $value, in: range, step: step)
                    .frame(maxWidth: .infinity)

                HStack {
                    Text(leadingHint)
                    Spacer(minLength: 0)
                    Text(valueText)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text(trailingHint)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// 离散档位滑条（仿「点按」弱/中/强）；文案按刻度位置对齐，避免等分居中错位。
private struct SettingsDiscreteSliderRow: View {
    let title: String
    @Binding var selection: Int
    let labels: [String]

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(selection) },
            set: { selection = Int($0.rounded()) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
                .padding(.top, 1)

            VStack(spacing: 2) {
                Slider(
                    value: sliderValue,
                    in: 0...Double(max(labels.count - 1, 1)),
                    step: 1
                )
                .frame(maxWidth: .infinity)

                DiscreteSliderTickLabels(labels: labels)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// 与系统 Slider 步进刻度对齐。
/// 系统刻度落在滑块行程两端（约半个拇指内缩），文案中心对准这些点。
private struct DiscreteSliderTickLabels: View {
    let labels: [String]
    /// 约等于 macOS Slider 拇指半径，使首尾字心对准两端刻度。
    private let thumbInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let count = labels.count
            let span = max(geo.size.width - thumbInset * 2, 1)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, text in
                let x: CGFloat = {
                    guard count > 1 else { return geo.size.width / 2 }
                    return thumbInset + span * CGFloat(index) / CGFloat(count - 1)
                }()
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: x, y: geo.size.height / 2)
            }
        }
        .frame(height: 12)
    }
}

/// 标签靠左 + 右侧开关（仿「用力点按和触感反馈」）。
private struct SettingsSwitchRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct IslandThemeChip: View {
    let theme: IslandTheme
    let selected: Bool
    let action: () -> Void

    private var palette: IslandPalette { theme.palette }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IslandThemeSwatch(palette: palette)

                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(theme.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct IslandThemeSwatch: View {
    let palette: IslandPalette

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: 10)
        HStack(spacing: 6) {
            Circle()
                .fill(palette.icon)
                .frame(width: 10, height: 10)
            Capsule()
                .fill(palette.accentFill)
                .frame(width: 36, height: 6)
            Capsule()
                .fill(palette.secondary)
                .frame(width: 18, height: 6)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Circle().fill(palette.pageDotActive).frame(width: 4, height: 4)
                Circle().fill(palette.pageDotInactive).frame(width: 4, height: 4)
                Circle().fill(palette.pageDotInactive).frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(shape.fill(palette.fill))
        .clipShape(shape)
    }
}
