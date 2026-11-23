import AppKit
import Foundation
import Network
import SystemConfiguration

/// 瞬时 tip 指标：连接态右翼**只示网关延迟**；SSID 由 Monitor 提供。
///
/// | 指标 | 能否拿到 | 来源 |
/// |---|---|---|
/// | 网关延迟 | 可以（TCP 握手） | 默认路由 → TCP connect |
/// | VPN 节点名 | **系统代理基本拿不到** | 退客户端 App 名 /「VPN」 |
enum NetworkLinkMetrics {
    /// 连接 tip 投递前最多等这么久补延迟；超时仍上岛（有啥示啥）。
    static let latencyBudget: TimeInterval = 0.35
    /// 网关延迟 ≥ 此值：右翼延迟字与状态点用警告黄；否则绿。
    static let latencyWarningMs: Int = 100

    enum LatencyTone: Equatable {
        case good
        case elevated
        case unknown
    }

    /// 按延迟数额判色调；无数值时保守用 good（绿）。
    static func latencyTone(ms: Int?) -> LatencyTone {
        guard let ms, ms > 0 else { return .unknown }
        return ms >= latencyWarningMs ? .elevated : .good
    }

    struct Enrichment: Equatable {
        var title: String
        var detail: String?
        var ssid: String?
        var latencyMs: Int?
    }

    static func enrich(
        kind: NetworkLinkTipKind,
        snap: NetworkLinkSnapshot,
        lastKnownWifiSSID: String? = nil,
        lastKnownVPNName: String? = nil
    ) async -> Enrichment {
        switch kind {
        case .wifiDisconnected:
            // 左翼优先展示断开前的 SSID；读不到再退「离线」。
            let ssid = Self.preferredSSID(snap.wifiSSID, lastKnownWifiSSID)
            let title = ssid ?? L10n.NetworkLink.offlineTitle
            return Enrichment(
                title: title,
                detail: L10n.NetworkLink.disconnectedBadge,
                ssid: ssid
            )
        case .vpnDisconnected:
            return Enrichment(
                title: vpnTitle(preferred: lastKnownVPNName),
                detail: L10n.NetworkLink.disconnectedBadge
            )
        case .wifiConnected:
            let ssid = Self.preferredSSID(snap.wifiSSID, lastKnownWifiSSID)
            let title = ssid ?? L10n.NetworkLink.wifiShort
            let latency = await gatewayLatencyMs(budget: latencyBudget)
            return Enrichment(
                title: title,
                detail: formatLatency(latency),
                ssid: ssid,
                latencyMs: latency
            )
        case .wiredConnected:
            let latency = await gatewayLatencyMs(budget: latencyBudget)
            return Enrichment(
                title: L10n.NetworkLink.wiredShort,
                detail: formatLatency(latency),
                latencyMs: latency
            )
        case .vpnConnected:
            // 与断开态同布局：盾牌+名称；右翼延迟+绿点（非「断开」/红点）。
            let latency = await gatewayLatencyMs(budget: latencyBudget)
            return Enrichment(
                title: vpnTitle(preferred: lastKnownVPNName),
                detail: formatLatency(latency),
                latencyMs: latency
            )
        }
    }

    /// VPN 显示名：系统服务名 / 代理客户端名 / 记忆名；否则「VPN」。
    static func vpnTitle(preferred: String? = nil) -> String {
        if let name = vpnDisplayName(), !name.isEmpty {
            return name
        }
        if let preferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
            return preferred
        }
        return L10n.NetworkLink.vpnShort
    }

    /// 尽力读 VPN / 隧道服务名；Clash 系统代理通常无节点名，退回客户端 App 名。
    static func vpnDisplayName() -> String? {
        if let system = systemVPNServiceName() {
            return system
        }
        if NetworkLinkMonitor.isSystemProxyActive(),
           let client = proxyClientDisplayName()
        {
            return client
        }
        return nil
    }

    /// 系统 Network 服务 / PPP / VPN 字典上的 UserDefinedName。
    static func systemVPNServiceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Ridge.NetworkLink.VPNName" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let serviceID = global["PrimaryService"] as? String,
              !serviceID.isEmpty
        else { return nil }

        let serviceKey = "State:/Network/Service/\(serviceID)" as CFString
        if let service = SCDynamicStoreCopyValue(store, serviceKey) as? [String: Any] {
            if let name = sanitizedVPNName(service["UserDefinedName"] as? String) {
                return name
            }
        }
        for suffix in ["PPP", "VPN", "Interface"] {
            let key = "State:/Network/Service/\(serviceID)/\(suffix)" as CFString
            if let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
               let name = sanitizedVPNName(dict["UserDefinedName"] as? String)
                ?? sanitizedVPNName(dict["ServerAddress"] as? String)
            {
                return name
            }
        }
        return nil
    }

    /// Clash / Surge 等走系统代理时：用正在跑的客户端名当展示名（节点名系统不暴露）。
    static func proxyClientDisplayName() -> String? {
        let hints: [(bundleID: String, name: String)] = [
            ("com.west2online.ClashXPro", "ClashX Pro"),
            ("com.west2online.ClashX", "ClashX"),
            ("io.github.clash-verge-rev.clash-verge-rev", "Clash Verge"),
            ("com.lbyczf.clashmeta", "Clash Meta"),
            ("com.metacubex.ClashMetaForAndroid", "Clash Meta"),
            ("com.nssurge.surge-mac", "Surge"),
            ("com.nssurge.surge-mac.Surge-Mac", "Surge"),
            ("com.v2rayu.app", "V2rayU"),
            ("com.v2rayn.macos", "V2rayN"),
            ("com.shadowsocks.osx", "Shadowsocks"),
            ("com.qiubee.Qv2ray", "Qv2ray")
        ]
        let running = NSWorkspace.shared.runningApplications
        for hint in hints {
            if running.contains(where: { $0.bundleIdentifier == hint.bundleID }) {
                return hint.name
            }
        }
        // 宽松：bundle id / 进程名含 clash / surge。
        for app in running {
            let bid = (app.bundleIdentifier ?? "").lowercased()
            let name = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if bid.contains("clash") || name.lowercased().contains("clash") {
                return sanitizedVPNName(name.isEmpty ? "Clash" : name)
            }
            if bid.contains("surge") || name.lowercased().contains("surge") {
                return sanitizedVPNName(name.isEmpty ? "Surge" : name)
            }
        }
        return nil
    }

    private static func sanitizedVPNName(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        // 过滤无意义的接口名 / 占位。
        let lower = s.lowercased()
        if lower.hasPrefix("utun") || lower.hasPrefix("en") || lower == "vpn" {
            return nil
        }
        if s.count > 24 { s = String(s.prefix(24)) }
        return s
    }

    static func formatLatency(_ ms: Int?) -> String? {
        guard let ms, ms > 0 else { return nil }
        return "\(ms)ms"
    }

    private static func preferredSSID(_ candidates: String?...) -> String? {
        for raw in candidates {
            if let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    // MARK: - Gateway latency (TCP handshake)

    static func gatewayAddress() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Ridge.NetworkLink.Metrics" as CFString, nil, nil),
              let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = info["Router"] as? String,
              !router.isEmpty
        else { return nil }
        return router
    }

    static func gatewayLatencyMs(budget: TimeInterval) async -> Int? {
        guard let host = gatewayAddress() else { return nil }
        if let ms = await tcpHandshakeLatencyMs(host: host, port: 53, budget: budget) {
            return ms
        }
        return await tcpHandshakeLatencyMs(host: host, port: 443, budget: min(budget, 0.2))
    }

    static func tcpHandshakeLatencyMs(host: String, port: UInt16, budget: TimeInterval) async -> Int? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "app.daphnis.Ridge.networkLink.latency")
            let started = Date()
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil)
                return
            }
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )
            let lock = NSLock()
            var finished = false
            let finish: (Int?) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = Int((Date().timeIntervalSince(started) * 1000.0).rounded())
                    finish(max(ms, 1))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + budget) {
                finish(nil)
            }
        }
    }
}
