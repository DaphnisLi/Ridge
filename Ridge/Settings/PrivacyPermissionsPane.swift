import AppKit
import CoreBluetooth
import CoreGraphics
import SwiftUI

/// 权限与隐私总览：只读状态 + 跳转系统设置 / 授权。
struct PrivacyPermissionsPane: View {
    @ObservedObject private var calendar = MeetingCalendarService.shared
    @State private var screenCaptureOK = CGPreflightScreenCaptureAccess()
    @State private var inputOK = ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
    @State private var bluetoothLabel = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                Text(L10n.PrivacyHub.intro)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)

                SettingsPaneSection(title: L10n.PrivacyHub.permissionsSection) {
                    permissionRow(
                        title: L10n.PrivacyHub.calendar,
                        detail: calendarStatusText,
                        granted: calendar.authStatus == .authorized
                    ) {
                        Task {
                            _ = await calendar.requestAccess()
                            refresh()
                        }
                    }

                    SettingsHairline()
                    permissionRow(
                        title: L10n.PrivacyHub.screenCapture,
                        detail: screenCaptureOK ? L10n.Common.authorized : L10n.PrivacyHub.notAuthorized,
                        granted: screenCaptureOK
                    ) {
                        _ = CGRequestScreenCaptureAccess()
                        openPrivacyPane("Privacy_ScreenCapture")
                        refresh()
                    }

                    SettingsHairline()
                    permissionRow(
                        title: L10n.PrivacyHub.inputMonitoring,
                        detail: inputOK ? L10n.Common.authorized : L10n.PrivacyHub.notAuthorized,
                        granted: inputOK
                    ) {
                        _ = ResourceKeystrokeMonitor.shared.requestInputMonitoringAccess()
                        refresh()
                    }

                    SettingsHairline()
                    permissionRow(
                        title: L10n.PrivacyHub.bluetooth,
                        detail: bluetoothLabel,
                        granted: bluetoothGranted
                    ) {
                        openPrivacyPane("Privacy_Bluetooth")
                        refresh()
                    }
                }

                SettingsPaneSection(title: L10n.About.legalSection) {
                    Button {
                        flashLegal(LegalDocumentOpener.open(.privacy))
                    } label: {
                        HStack {
                            Text(L10n.About.privacyPolicy)
                                .font(SettingsChrome.Font.rowTitle)
                                .foregroundStyle(SettingsChrome.primary)
                            Spacer()
                        }
                        .padding(SettingsChrome.Spacing.cardPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
            .padding(.vertical, 20)
        }
        .onAppear {
            refresh()
            AppLog.warn("Settings", "权限与隐私页已显示")
        }
    }

    private var bluetoothGranted: Bool {
        switch CBManager.authorization {
        case .allowedAlways: return true
        default: return false
        }
    }

    private var calendarStatusText: String {
        switch calendar.authStatus {
        case .authorized: return L10n.Common.authorized
        case .denied, .restricted: return L10n.PrivacyHub.denied
        case .notDetermined: return L10n.PrivacyHub.notDetermined
        }
    }

    private func refresh() {
        calendar.refreshAuthStatus()
        screenCaptureOK = CGPreflightScreenCaptureAccess()
        inputOK = ResourceKeystrokeMonitor.shared.hasInputMonitoringAccess
        switch CBManager.authorization {
        case .allowedAlways:
            bluetoothLabel = L10n.Common.authorized
        case .denied:
            bluetoothLabel = L10n.PrivacyHub.denied
        case .restricted:
            bluetoothLabel = L10n.PrivacyHub.denied
        case .notDetermined:
            bluetoothLabel = L10n.PrivacyHub.notDetermined
        @unknown default:
            bluetoothLabel = L10n.PrivacyHub.notDetermined
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsChrome.Font.rowTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(detail)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(granted ? SettingsChrome.secondary : SettingsChrome.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            Button(granted ? L10n.PrivacyHub.manageInSystem : L10n.Common.authorize) {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
        .padding(.vertical, 12)
    }

    private func openPrivacyPane(_ anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                AppLog.info("PrivacyHub", "已打开系统隐私设置", ["url": raw])
                return
            }
        }
        AppLog.warn("PrivacyHub", "无法打开系统隐私设置", ["anchor": anchor])
    }

    private func flashLegal(_ ok: Bool) {
        if !ok {
            AppLog.warn("PrivacyHub", "打开隐私政策失败")
        }
    }
}
