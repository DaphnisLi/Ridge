import SwiftUI

/// 「电量与外设」预览页：岛预览 + 告警设置 + 低电/满电提示卡样张。
struct BatteryWidgetConfigSection: View {
    @ObservedObject private var settings = BatterySettings.shared
    @ObservedObject private var session = BatterySession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            islandPreviewCard
            headerBlock
            lowAlertCard
            fullAlertCard
            tipWidgetsCard
        }
        .onAppear {
            session.start()
            session.refresh(reason: "batteryConfigAppear")
            AppLog.info("Battery", "电量配置预览页已显示", [
                "low": settings.lowAlertEnabled,
                "threshold": settings.lowThresholdPercent,
                "full": settings.fullChargeAlertEnabled,
                "devices": session.devices.count
            ])
        }
    }

    // MARK: - 岛预览

    private var islandPreviewCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                WidgetSamplePreview.island(for: "system.controlDeck.battery", compact: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        SettingsChrome.surfaceContainerLow,
                        SettingsChrome.surfaceContainer.opacity(0.50)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.ControlDeck.moduleBattery)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.Battery.alertsIntro)
                .font(.system(size: 13))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 低电

    private var lowAlertCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSwitchRow(
                    title: L10n.Battery.forceExpandTitle,
                    subtitle: L10n.Battery.forceExpandSubtitle,
                    isOn: $settings.lowAlertEnabled
                )

                if settings.lowAlertEnabled {
                    Divider().padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.Battery.lowThreshold)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SettingsChrome.onSurface)
                            Spacer(minLength: 8)
                            Text("\(settings.lowThresholdPercent)%")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.lowThresholdPercent) },
                                set: { settings.lowThresholdPercent = Int($0.rounded()) }
                            ),
                            in: 5...40,
                            step: 1
                        )
                        Text(L10n.Battery.lowThresholdHint(settings.lowThresholdPercent))
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        Text(L10n.Battery.snoozeHint)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - 满电

    private var fullAlertCard: some View {
        SettingsCard {
            SettingsSwitchRow(
                title: L10n.Battery.fullAlertToggle,
                subtitle: L10n.Battery.fullAlertHint,
                isOn: $settings.fullChargeAlertEnabled
            )
        }
    }

    // MARK: - 两张提示样张

    private var tipWidgetsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Battery.tipSectionTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Battery.tipSectionSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                VStack(spacing: 10) {
                    BatteryTipPreviewCard(
                        style: .low,
                        deviceName: L10n.Battery.tipSampleMouse,
                        percent: 12,
                        detail: L10n.Battery.tipSampleLowDetail(settings.lowThresholdPercent),
                        footer: L10n.Battery.tipSampleLowFooter(settings.lowThresholdPercent)
                    )
                    BatteryTipPreviewCard(
                        style: .full,
                        deviceName: L10n.Battery.tipSampleKeyboard,
                        percent: 100,
                        detail: L10n.Battery.tipSampleFullDetail,
                        footer: L10n.Battery.tipSampleFullFooter
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    Button(L10n.Battery.previewLowNotice) {
                        presentSampleNotice(low: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(L10n.Battery.previewFullNotice) {
                        presentSampleNotice(low: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private func presentSampleNotice(low: Bool) {
        let threshold = settings.lowThresholdPercent
        if low {
            let notice = BatteryPeripheralNotice(
                id: "battery.preview.low.\(UUID().uuidString.prefix(8))",
                deviceID: "preview.mouse",
                deviceName: L10n.Battery.tipSampleMouse,
                kind: .mouse,
                percent: 12,
                threshold: threshold,
                detail: L10n.Battery.lowNoticeDetail(12, threshold)
            )
            IslandNoticeCenter.shared.present(.peripheralLowBattery(notice))
            AppLog.info("Battery", "设置页试投低电提示")
        } else {
            let notice = BatteryPeripheralNotice(
                id: "battery.preview.full.\(UUID().uuidString.prefix(8))",
                deviceID: "preview.keyboard",
                deviceName: L10n.Battery.tipSampleKeyboard,
                kind: .keyboard,
                percent: 100,
                threshold: 100,
                detail: L10n.Battery.fullNoticeDetail
            )
            IslandNoticeCenter.shared.present(.peripheralFullCharge(notice))
            AppLog.info("Battery", "设置页试投满电提示")
        }
    }
}

// MARK: - 设置页内的提示卡样张（深色岛形）

struct BatteryTipPreviewCard: View {
    enum Style {
        case low
        case full
    }

    let style: Style
    let deviceName: String
    let percent: Int
    let detail: String
    let footer: String

    private let accentRed = Color(red: 0.729, green: 0.102, blue: 0.102)
    private let accentGreen = Color(red: 0.447, green: 0.996, blue: 0.533)

    private var accent: Color { style == .low ? accentRed : accentGreen }
    private var symbol: String {
        style == .low ? "computermouse" : "keyboard"
    }

    var body: some View {
        Group {
            if style == .full {
                fullPreview
            } else {
                lowPreview
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var fullPreview: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(accentGreen.opacity(0.85), lineWidth: 1.2)
                        )
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                .frame(width: 30, height: 30)
                .shadow(color: accentGreen.opacity(0.75), radius: 7, x: 0, y: 0)
                .shadow(color: accentGreen.opacity(0.40), radius: 14, x: 0, y: 0)

                ZStack {
                    Circle()
                        .fill(accentGreen)
                        .frame(width: 12, height: 12)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                }
                .offset(x: 3, y: 3)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(deviceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n.Battery.tipFullBadge)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(accentGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(accentGreen.opacity(0.14))
                    .overlay(
                        Capsule().strokeBorder(accentGreen.opacity(0.75), lineWidth: 1)
                    )
            )
            .shadow(color: accentGreen.opacity(0.70), radius: 8, x: 0, y: 0)
            .fixedSize()
        }
    }

    private var lowPreview: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(accentRed.opacity(0.90), lineWidth: 1.2)
                        )
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentRed)
                }
                .frame(width: 30, height: 30)
                .shadow(color: accentRed.opacity(0.80), radius: 7, x: 0, y: 0)
                .shadow(color: accentRed.opacity(0.45), radius: 14, x: 0, y: 0)

                ZStack {
                    Circle()
                        .fill(accentRed)
                        .frame(width: 12, height: 12)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                }
                .offset(x: 3, y: -3)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(deviceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                // 设置页样张：静态两格，岛上通知才循环动画。
                HStack(spacing: 1.2) {
                    HStack(spacing: 1.4) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                                .fill(index < 2 ? Color.white : Color.white.opacity(0.22))
                                .frame(width: 2.4, height: 6.5)
                        }
                    }
                    .padding(.horizontal, 2.2)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
                    )
                    RoundedRectangle(cornerRadius: 0.6, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 1.4, height: 3.2)
                }

                Text(L10n.Battery.tipLowBadge(percent))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(accentRed))
            .shadow(color: accentRed.opacity(0.75), radius: 7, x: 0, y: 0)
            .fixedSize()
        }
    }
}
