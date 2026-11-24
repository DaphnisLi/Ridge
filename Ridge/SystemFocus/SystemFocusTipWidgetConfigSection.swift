import AppKit
import SwiftUI

/// 系统 Focus tip 设置：完全磁盘访问 + 开/关两态样张。
struct SystemFocusTipWidgetConfigSection: View {
    @ObservedObject private var session = SystemFocusSession.shared
    @State private var previewSelection = SystemFocusNoticeCard.PreviewVariant.onUntil.rawValue

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    diskAccessCard
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
            SystemFocusSession.shared.start()
            SystemFocusSession.shared.recheckAccess(reason: "configAppear")
            AppLog.info("SystemFocus", "配置页已显示", [
                "canRead": session.canReadStore,
                "active": session.latest.isActive,
                "mode": session.latest.mode?.name ?? ""
            ])
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            SystemFocusSession.shared.recheckAccess(reason: "appActive")
        }
    }

    @ViewBuilder
    private var diskAccessCard: some View {
        SettingsPermissionCard(
            status: session.canReadStore ? .authorized : .openSettings,
            symbol: "internaldrive",
            tint: SettingsChrome.primary,
            title: L10n.SystemFocus.diskAccessTitle,
            subtitle: session.canReadStore
                ? L10n.SystemFocus.diskAccessGrantedDesc
                : L10n.SystemFocus.diskAccessDesc,
            requestTitle: L10n.SystemFocus.diskAccessAllow,
            requestSymbol: "arrow.up.forward.app",
            action: session.canReadStore ? nil : {
                AppLog.warn("SystemFocus", "设置页打开完全磁盘访问")
                SystemPrivacyOpener.open(anchor: "Privacy_AllFiles")
            }
        )
    }

    private var previewStage: some View {
        SettingsIslandStage(
            options: SystemFocusNoticeCard.PreviewVariant.allCases.map { variant in
                SettingsIslandStageOption(
                    id: variant.rawValue,
                    title: previewTitle(variant),
                    badge: previewBadge(variant),
                    symbol: variant == .onUntil ? "moon.fill" : "bed.double.fill",
                    tint: variant == .off
                        ? SettingsChrome.onSurfaceVariant
                        : (variant == .onUntil
                            ? SystemFocusPalette.activeAccent
                            : Color(nsColor: .systemMint)),
                    maxIslandWidth: SettingsIslandPreviewWidth.tip,
                    hugsContent: WidgetSamplePreview.tipPreviewHugsContent,
                    outlineStyle: .panel,
                    minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
                    compactShell: true
                )
            },
            selection: $previewSelection
        ) { option in
            WidgetSamplePreview.content(
                for: "builtin.systemFocusTip.\(option.id)",
                compact: true
            )
        }
    }

    private func previewTitle(_ variant: SystemFocusNoticeCard.PreviewVariant) -> String {
        switch variant {
        case .onUntil: return L10n.SystemFocus.previewOnUntil
        case .onOpened: return L10n.SystemFocus.previewOnOpened
        case .off: return L10n.SystemFocus.previewOff
        }
    }

    private func previewBadge(_ variant: SystemFocusNoticeCard.PreviewVariant) -> String {
        switch variant {
        case .onUntil: return L10n.SystemFocus.untilTime("18:00")
        case .onOpened: return L10n.SystemFocus.openedBadge
        case .off: return L10n.SystemFocus.closedBadge
        }
    }
}
