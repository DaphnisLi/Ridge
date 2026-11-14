import AppKit
import ApplicationServices
import CoreBluetooth
import CoreGraphics
import SwiftUI

/// 通用设置与权限：开机自启 + 系统权限状态。
struct GeneralSettingsPane: View {
    @ObservedObject private var loginItem = LoginItemService.shared
    @ObservedObject private var calendar = MeetingCalendarService.shared

    @State private var screenCaptureOK = CGPreflightScreenCaptureAccess()
    @State private var inputOK = ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
    @State private var accessibilityOK = AXIsProcessTrusted()
    @State private var bluetoothOK = false

    private var grantedCount: Int {
        [
            calendar.authStatus == .authorized,
            screenCaptureOK,
            inputOK,
            bluetoothOK,
            accessibilityOK
        ].filter(\.self).count
    }

    private let permissionTotal = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                launchCard
                permissionsCard
            }
            .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            loginItem.refresh()
            refreshPermissions()
            AppLog.warn("Settings", "通用设置页已显示", [
                "loginItem": loginItem.isEnabled,
                "granted": grantedCount
            ])
        }
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissions()
        }
    }

    // MARK: - Launch

    private var launchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.General.launchSection)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "power.circle.fill")
                            .font(SettingsChrome.Font.iconTile)
                            .foregroundStyle(SettingsChrome.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(SettingsChrome.surfaceContainer)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.General.launchAtLogin)
                                .font(SettingsChrome.Font.sectionTitle)
                                .foregroundStyle(SettingsChrome.onSurface)
                            Text(L10n.General.launchAtLoginSubtitle)
                                .font(SettingsChrome.Font.caption)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        }

                        Spacer(minLength: 8)

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { loginItem.isEnabled },
                                set: { next in
                                    let ok = loginItem.setEnabled(next)
                                    if !ok {
                                        loginItem.openSystemLoginItemsSettings()
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(L10n.General.launchAtLogin)
                    }
                    .padding(SettingsChrome.Spacing.cardPadding)

                    if let err = loginItem.lastError, !err.isEmpty {
                        Text(err)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.error)
                            .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.General.permissionsSection)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .textCase(.uppercase)
                Circle()
                    .fill(SettingsChrome.secondary)
                    .frame(width: 6, height: 6)
                Spacer(minLength: 0)
                Text(L10n.General.permissionsReadyCount(grantedCount, permissionTotal))
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            .padding(.horizontal, 4)

            SettingsCard {
                VStack(spacing: 0) {
                    permissionRow(
                        symbol: "calendar",
                        title: L10n.PrivacyHub.calendarTitle,
                        subtitle: L10n.PrivacyHub.calendarSubtitle,
                        granted: calendar.authStatus == .authorized
                    ) {
                        Task {
                            _ = await calendar.requestAccess()
                            refreshPermissions()
                        }
                    }
                    SettingsHairline()
                    permissionRow(
                        symbol: "rectangle.dashed.badge.record",
                        title: L10n.PrivacyHub.screenCaptureTitle,
                        subtitle: L10n.PrivacyHub.screenCaptureSubtitle,
                        granted: screenCaptureOK
                    ) {
                        _ = CGRequestScreenCaptureAccess()
                        SystemPrivacyOpener.open(anchor: "Privacy_ScreenCapture")
                        refreshPermissions()
                    }
                    SettingsHairline()
                    permissionRow(
                        symbol: "keyboard",
                        title: L10n.PrivacyHub.inputMonitoringTitle,
                        subtitle: L10n.PrivacyHub.inputMonitoringSubtitle,
                        granted: inputOK,
                        emphasizePending: !inputOK
                    ) {
                        _ = ResourceKeystrokeMonitor.shared.requestInputMonitoringAccess()
                        refreshPermissions()
                    }
                    SettingsHairline()
                    permissionRow(
                        symbol: "antenna.radiowaves.left.and.right",
                        title: L10n.PrivacyHub.bluetoothTitle,
                        subtitle: L10n.PrivacyHub.bluetoothSubtitle,
                        granted: bluetoothOK
                    ) {
                        SystemPrivacyOpener.open(anchor: "Privacy_Bluetooth")
                        refreshPermissions()
                    }
                    SettingsHairline()
                    permissionRow(
                        symbol: "accessibility",
                        title: L10n.PrivacyHub.accessibilityTitle,
                        subtitle: L10n.PrivacyHub.accessibilitySubtitle,
                        granted: accessibilityOK
                    ) {
                        SystemPrivacyOpener.open(anchor: "Privacy_Accessibility")
                        refreshPermissions()
                    }
                }
            }
        }
    }

    private func permissionRow(
        symbol: String,
        title: String,
        subtitle: String,
        granted: Bool,
        emphasizePending: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(SettingsChrome.Font.iconTile)
                .foregroundStyle(granted ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(granted ? SettingsChrome.surfaceContainer : SettingsChrome.surfaceContainerHighest)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    if emphasizePending, !granted {
                        Text(L10n.PrivacyHub.pendingBadge)
                            .font(SettingsChrome.Font.badgeTiny)
                            .foregroundStyle(SettingsChrome.error)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(SettingsChrome.error.opacity(0.12))
                            )
                    }
                }
                Text(subtitle)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if granted {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SettingsChrome.secondary)
                        .frame(width: 6, height: 6)
                    Text(L10n.Common.authorized)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSecondaryContainer)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(SettingsChrome.secondaryContainer.opacity(0.55))
                )
            } else {
                Button {
                    action()
                } label: {
                    Label(L10n.PrivacyHub.goAuthorize, systemImage: "arrow.up.right.square")
                        .font(SettingsChrome.Font.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(SettingsChrome.primary)
            }
        }
        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
        .padding(.vertical, 12)
        .background(emphasizePending && !granted ? SettingsChrome.surfaceContainerLow.opacity(0.7) : Color.clear)
    }

    private func refreshPermissions() {
        calendar.refreshAuthStatus()
        screenCaptureOK = CGPreflightScreenCaptureAccess()
        inputOK = ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
        accessibilityOK = AXIsProcessTrusted()
        bluetoothOK = {
            switch CBManager.authorization {
            case .allowedAlways: return true
            default: return false
            }
        }()
    }
}
