import Combine
import Foundation
import Network
import SystemConfiguration

/// 网络 / VPN 监测：主路径切换与 VPN/系统代理通断 → 瞬时 tip；非常驻页。
@MainActor
final class NetworkLinkSession: ObservableObject {
    static let shared = NetworkLinkSession()

    @Published private(set) var latest = NetworkLinkSnapshot(
        medium: .none,
        vpnActive: false,
        wifiSSID: nil
    )

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "app.daphnis.Ridge.networkLink")
    private var policy = NetworkLinkTipPolicy()
    private var tickTimer: Timer?
    private var started = false
    private var seeded = false
    /// 断开 tip 左翼用：掉线时 path 已无 SSID，需记住上一跳 Wi‑Fi 名。
    private var lastKnownWifiSSID: String?
    /// VPN 断开时系统服务 / 代理客户端名已不可读，记住上一跳展示名。
    private var lastKnownVPNName: String?

    private var dynamicStore: SCDynamicStore?
    private var dynamicStoreSource: CFRunLoopSource?

    private init() {}

    private var tipEnabled: Bool {
        WidgetSettings.shared.isEnabled(NetworkLinkTipWidget.manifest.id)
    }

    func start() {
        guard !started else {
            AppLog.debug("NetworkLink", "会话已在跑，跳过重复 start")
            return
        }
        started = true
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePath(path, reason: "pathUpdate")
            }
        }
        pathMonitor.start(queue: queue)
        monitor = pathMonitor
        startDynamicStore()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushTicks()
            }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
        // 不在此处播种：`currentPath` 启动瞬间常为 nil，会先记成 other 再被 pathUpdate
        // 打成 wifi → 误 tip「已连接」。等 pathUpdate / dynamicStore 第一条再 seed。
        let probe = NetworkLinkMonitor.snapshot(from: monitor?.currentPath)
        AppLog.warn("NetworkLink", "网络 tip 会话已启动", [
            "tipOn": tipEnabled,
            "medium": probe.medium.rawValue,
            "vpn": probe.vpnActive,
            "primary": NetworkLinkMonitor.primaryInterfaceName() ?? "",
            "proxy": NetworkLinkMonitor.isSystemProxyActive(),
            "pathReady": monitor?.currentPath != nil
        ])
    }

    func stop() {
        guard started else { return }
        monitor?.cancel()
        monitor = nil
        stopDynamicStore()
        tickTimer?.invalidate()
        tickTimer = nil
        started = false
        seeded = false
        lastKnownWifiSSID = nil
        lastKnownVPNName = nil
        policy.reset()
        AppLog.warn("NetworkLink", "网络 tip 会话已停止")
    }

    func refresh(reason: String) {
        ingestCurrent(reason: reason)
    }

    // MARK: - Dynamic store（代理 / 主接口；Clash 切系统代理时 path 往往不变）

    private func startDynamicStore() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(
            nil,
            "app.daphnis.Ridge.NetworkLink" as CFString,
            { _, _, _ in
                Task { @MainActor in
                    NetworkLinkSession.shared.ingestCurrent(reason: "dynamicStore")
                }
            },
            &context
        ) else {
            AppLog.warn("NetworkLink", "SCDynamicStore 创建失败")
            return
        }
        let keys: [CFString] = [
            "State:/Network/Global/IPv4" as CFString,
            "State:/Network/Global/IPv6" as CFString,
            "State:/Network/Global/Proxies" as CFString
        ]
        let patterns: [CFString] = [
            "State:/Network/Interface/.*/AirPort" as CFString,
            "Setup:/Network/Interface/.*/AirPort" as CFString
        ]
        SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray)
        guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else {
            AppLog.warn("NetworkLink", "SCDynamicStore RunLoopSource 创建失败")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        dynamicStore = store
        dynamicStoreSource = source
        AppLog.warn("NetworkLink", "已订阅主接口与系统代理变化")
    }

    private func stopDynamicStore() {
        if let source = dynamicStoreSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        dynamicStoreSource = nil
        dynamicStore = nil
    }

    // MARK: - Ingest

    private func handlePath(_ path: NWPath, reason: String) {
        apply(NetworkLinkMonitor.snapshot(from: path), reason: reason)
    }

    private func ingestCurrent(reason: String) {
        apply(NetworkLinkMonitor.snapshot(from: monitor?.currentPath), reason: reason)
    }

    private func apply(_ snap: NetworkLinkSnapshot, reason: String) {
        let changed = snap != latest
        latest = snap
        if let ssid = snap.wifiSSID, !ssid.isEmpty {
            lastKnownWifiSSID = ssid
        }
        if snap.vpnActive, let vpnName = NetworkLinkMetrics.vpnDisplayName(), !vpnName.isEmpty {
            lastKnownVPNName = vpnName
        }

        if !seeded {
            seeded = true
            _ = policy.ingest(snap)
            AppLog.warn("NetworkLink", "网络状态已播种", [
                "reason": reason,
                "medium": snap.medium.rawValue,
                "vpn": snap.vpnActive,
                "ssid": snap.wifiSSID ?? "",
                "vpnName": lastKnownVPNName ?? "",
                "location": NetworkLinkLocationAccess.describe(
                    NetworkLinkLocationAccess.shared.status
                ),
                "primary": NetworkLinkMonitor.primaryInterfaceName() ?? "",
                "proxy": NetworkLinkMonitor.isSystemProxyActive(),
                "tipOn": tipEnabled
            ])
            return
        }

        if changed {
            AppLog.warn("NetworkLink", "网络状态变化", [
                "reason": reason,
                "medium": snap.medium.rawValue,
                "vpn": snap.vpnActive,
                "ssid": snap.wifiSSID ?? "",
                "vpnName": lastKnownVPNName ?? "",
                "location": NetworkLinkLocationAccess.describe(
                    NetworkLinkLocationAccess.shared.status
                ),
                "primary": NetworkLinkMonitor.primaryInterfaceName() ?? "",
                "proxy": NetworkLinkMonitor.isSystemProxyActive(),
                "tipOn": tipEnabled
            ])
        }

        let kinds = policy.ingest(snap)
        guard tipEnabled else { return }
        for kind in kinds {
            present(kind: kind, snap: snap, reason: reason)
        }
    }

    private func flushTicks() {
        let kinds = policy.tick()
        guard tipEnabled, !kinds.isEmpty else { return }
        for kind in kinds {
            present(kind: kind, snap: latest, reason: "coalesceFlush")
        }
    }

    private func present(kind: NetworkLinkTipKind, snap: NetworkLinkSnapshot, reason: String) {
        let rememberedSSID = lastKnownWifiSSID
        let rememberedVPN = lastKnownVPNName
        switch kind {
        case .wifiConnected, .wifiDisconnected:
            // 首次 tip 时若尚未授权，顺带请求；本条可能仍无 SSID，授权后下一次可读。
            NetworkLinkLocationAccess.shared.ensureAuthorizedIfNeeded(reason: "present:\(kind.rawValue)")
        default:
            break
        }
        Task { @MainActor in
            let enrichment = await NetworkLinkMetrics.enrich(
                kind: kind,
                snap: snap,
                lastKnownWifiSSID: rememberedSSID,
                lastKnownVPNName: rememberedVPN
            )
            if snap.vpnActive || kind == .vpnConnected || kind == .vpnDisconnected {
                if enrichment.title != L10n.NetworkLink.vpnShort {
                    lastKnownVPNName = enrichment.title
                }
            }
            let notice = NetworkLinkNotice(
                id: "network.\(kind.rawValue).\(UUID().uuidString.prefix(8))",
                kind: kind,
                title: enrichment.title,
                detail: enrichment.detail,
                ssid: enrichment.ssid,
                latencyMs: enrichment.latencyMs
            )
            let payload: IslandNoticePayload
            switch kind {
            case .wifiConnected: payload = .networkWifiConnected(notice)
            case .wiredConnected: payload = .networkWiredConnected(notice)
            case .vpnConnected: payload = .networkVPNConnected(notice)
            case .wifiDisconnected: payload = .networkWifiDisconnected(notice)
            case .vpnDisconnected: payload = .networkVPNDisconnected(notice)
            }
            IslandNoticeCenter.shared.present(payload)
            AppLog.warn("NetworkLink", "已投递网络 tip", [
                "kind": kind.rawValue,
                "reason": reason,
                "title": enrichment.title,
                "detail": enrichment.detail ?? "",
                "latencyMs": enrichment.latencyMs ?? -1,
                "medium": snap.medium.rawValue,
                "vpn": snap.vpnActive
            ])
        }
    }
}
