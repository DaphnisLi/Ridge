import SwiftUI

/// 网络 / VPN tip 设置：定位授权（SSID）+ 五态样张。
struct NetworkLinkTipWidgetConfigSection: View {
    @ObservedObject private var location = NetworkLinkLocationAccess.shared
    @State private var previewSelection = NetworkLinkTipKind.wifiConnected.rawValue
    @State private var isRequestingLocation = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    locationPermissionCard
                    previewStage
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            NetworkLinkSession.shared.start()
            AppLog.info("NetworkLink", "配置页已显示", [
                "medium": NetworkLinkSession.shared.latest.medium.rawValue,
                "vpn": NetworkLinkSession.shared.latest.vpnActive,
                "location": NetworkLinkLocationAccess.describe(location.status)
            ])
        }
    }

    @ViewBuilder
    private var locationPermissionCard: some View {
        SettingsPermissionCard(
            status: locationPermissionStatus,
            symbol: "location.fill",
            tint: SettingsChrome.primary,
            title: L10n.NetworkLink.locationAccessTitle,
            subtitle: locationPermissionSubtitle,
            requestTitle: L10n.NetworkLink.locationAccessAllow,
            requestSymbol: "wifi",
            action: locationPermissionAction
        )
    }

    private var locationPermissionStatus: SettingsPermissionCard.Status {
        if location.isAuthorized { return .authorized }
        if location.needsRequest {
            return isRequestingLocation ? .busy : .request
        }
        if location.isDeniedOrRestricted { return .openSettings }
        return .openSettings
    }

    private var locationPermissionSubtitle: String {
        if location.isDeniedOrRestricted {
            return L10n.NetworkLink.locationAccessDeniedDesc
        }
        return L10n.NetworkLink.locationAccessDesc
    }

    private var locationPermissionAction: (() -> Void)? {
        if location.isAuthorized { return nil }
        return {
            guard !isRequestingLocation else { return }
            isRequestingLocation = true
            location.requestAccessFromSettings()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                isRequestingLocation = false
            }
        }
    }

    private var previewStage: some View {
        SettingsIslandStage(
            options: NetworkLinkTipKind.allCases.map { kind in
                tipOption(
                    id: kind.rawValue,
                    title: previewTitle(kind),
                    badge: previewBadge(kind),
                    symbol: previewSymbol(kind),
                    tint: previewTint(kind)
                )
            },
            selection: $previewSelection
        ) { option in
            WidgetSamplePreview.content(
                for: "builtin.networkLinkTip.\(option.id)",
                compact: true
            )
        }
    }

    private func tipOption(
        id: String,
        title: String,
        badge: String,
        symbol: String,
        tint: Color
    ) -> SettingsIslandStageOption {
        SettingsIslandStageOption(
            id: id,
            title: title,
            badge: badge,
            symbol: symbol,
            tint: tint,
            maxIslandWidth: SettingsIslandPreviewWidth.tip,
            hugsContent: WidgetSamplePreview.tipPreviewHugsContent,
            bottomRadius: 18,
            outlineStyle: .panel,
            minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
            compactShell: true
        )
    }

    private func previewTitle(_ kind: NetworkLinkTipKind) -> String {
        switch kind {
        case .wifiConnected: return L10n.NetworkLink.previewWifiConnected
        case .wiredConnected: return L10n.NetworkLink.previewWiredConnected
        case .vpnConnected: return L10n.NetworkLink.previewVPNConnected
        case .wifiDisconnected: return L10n.NetworkLink.previewWifiDisconnected
        case .vpnDisconnected: return L10n.NetworkLink.previewVPNDisconnected
        }
    }

    private func previewBadge(_ kind: NetworkLinkTipKind) -> String {
        switch kind {
        case .wifiConnected: return "Wi‑Fi"
        case .wiredConnected: return L10n.NetworkLink.wiredShort
        case .vpnConnected: return "VPN"
        case .wifiDisconnected, .vpnDisconnected: return L10n.NetworkLink.disconnectedBadge
        }
    }

    private func previewSymbol(_ kind: NetworkLinkTipKind) -> String {
        switch kind {
        case .wifiConnected: return "wifi"
        case .wiredConnected: return "cable.connector"
        case .vpnConnected: return "lock.shield.fill"
        case .wifiDisconnected: return "wifi.slash"
        case .vpnDisconnected: return "lock.open"
        }
    }

    private func previewTint(_ kind: NetworkLinkTipKind) -> Color {
        switch kind {
        case .wifiConnected, .wiredConnected, .vpnConnected:
            return SettingsChrome.secondary
        case .wifiDisconnected, .vpnDisconnected:
            return SettingsChrome.onSurfaceVariant
        }
    }
}
