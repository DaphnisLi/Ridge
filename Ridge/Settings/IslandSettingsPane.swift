import SwiftUI

struct IslandSettingsPane: View {
    @ObservedObject var settings: IslandSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsCard {
                    VStack(spacing: 14) {
                        // 收起态固定贴合刘海，不随宽高倍率变化。
                        IslandCompactPreview()
                        Text("收起 · 贴合刘海")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        IslandExpandedPreview(
                            bottomRadius: settings.bottomCornerRadius,
                            widthScale: settings.expandedWidthScale,
                            heightScale: settings.expandedHeightScale
                        )
                        Text("展开后 · 随下方倍率变化")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("外观")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("展开后宽度")
                                Spacer()
                                Text(String(format: "%.1f×", settings.expandedWidthScale))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.expandedWidthScale, in: 1.2...4.0, step: 0.1)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("展开后高度")
                                Spacer()
                                Text(String(format: "%.1f×", settings.expandedHeightScale))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.expandedHeightScale, in: 1.5...6.0, step: 0.1)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("下圆角")
                                Spacer()
                                Text("\(Int(settings.bottomCornerRadius.rounded())) pt")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.bottomCornerRadius, in: 0...36, step: 1)
                        }
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("行为")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("展开动画速度")
                                Spacer()
                                Text(String(format: "%.1f×", settings.animationSpeed))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.animationSpeed, in: 0.5...2.0, step: 0.1)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("震感强度")
                                Spacer()
                                Text(settings.hapticIntensity.title)
                                    .foregroundStyle(.secondary)
                            }
                            Picker("震感强度", selection: $settings.hapticIntensity) {
                                ForEach(IslandHapticIntensity.allCases) { level in
                                    Text(level.title).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        Divider()

                        Toggle("全屏时禁用灵动岛", isOn: $settings.hideInFullscreen)
                    }
                }

                SettingsCard {
                    Button("恢复默认设置") {
                        settings.restoreDefaults()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .background(Color.white)
        .onChange(of: settings.animationSpeed) { _, value in
            AppLog.info("Settings", "动画速度已更新", ["speed": value])
        }
        .onChange(of: settings.hideInFullscreen) { _, value in
            AppLog.info("Settings", "全屏禁用岛", ["enabled": value])
        }
        .onChange(of: settings.hapticIntensity) { _, value in
            AppLog.info("Settings", "震感强度", ["level": value.rawValue])
        }
        .onChange(of: settings.bottomCornerRadius) { _, value in
            AppLog.info("Settings", "下圆角已更新", ["radius": value])
        }
        .onChange(of: settings.expandedWidthScale) { _, value in
            AppLog.info("Settings", "展开宽度倍率", ["scale": value])
        }
        .onChange(of: settings.expandedHeightScale) { _, value in
            AppLog.info("Settings", "展开高度倍率", ["scale": value])
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

/// 收起态预览：固定尺寸，不受展开倍率影响。
private struct IslandCompactPreview: View {
    var body: some View {
        let shape = IslandPanelShape(bottomRadius: 10)
        Color.clear
            .frame(width: 168, height: 34)
            .background(shape.fill(Color.black))
            .clipShape(shape)
            .frame(maxWidth: .infinity)
    }
}

/// 展开态预览：随宽高倍率缩放。
private struct IslandExpandedPreview: View {
    let bottomRadius: Double
    let widthScale: Double
    let heightScale: Double

    var body: some View {
        // 预览按倍率相对默认 2×/3× 缩放，上限避免撑破卡片。
        let previewWidth = min(520, 180 * widthScale / 2.0)
        let previewHeight = min(120, 52 * heightScale / 3.0)
        let radius = min(bottomRadius, previewHeight / 2, previewWidth / 2)
        let shape = IslandPanelShape(bottomRadius: radius)

        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                )
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 54, height: 8)
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 8)
        }
        .padding(.horizontal, 18)
        .frame(width: previewWidth, height: previewHeight)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: widthScale)
        .animation(.easeInOut(duration: 0.15), value: heightScale)
        .animation(.easeInOut(duration: 0.15), value: bottomRadius)
    }
}
