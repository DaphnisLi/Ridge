import Foundation
import Network
import SystemConfiguration
#if canImport(CoreWLAN)
import CoreWLAN
#endif

/// 读主路径 + VPN/系统代理；SSID / 速率尽力而为。
enum NetworkLinkMonitor {
    static func snapshot(from path: NWPath?) -> NetworkLinkSnapshot {
        let primary = primaryInterfaceName()
        let medium = primaryMedium(path: path, primary: primary)
        let vpn = isTunnelPrimary(primary) || isSystemProxyActive()
        let ssid: String? = {
            guard medium == .wifi else { return nil }
            return sanitizedSSID(currentWiFiSSID())
        }()
        return NetworkLinkSnapshot(
            medium: medium,
            vpnActive: vpn,
            wifiSSID: ssid
        )
    }

    /// 当前 IPv4 主接口名（如 `en0` / `utun4`）。
    static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Ridge.NetworkLink" as CFString, nil, nil),
              let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = info["PrimaryInterface"] as? String,
              !name.isEmpty
        else { return nil }
        return name
    }

    static func primaryMedium(path: NWPath?, primary: String?) -> NetworkLinkMedium {
        if let path {
            let fromPath = mediumFromPath(path)
            if fromPath != .none { return fromPath }
        }
        guard let primary, !primary.isEmpty else { return .none }
        if isTunnelInterfaceName(primary) { return .other }
        if primary.hasPrefix("en") || primary.hasPrefix("eth") || primary.hasPrefix("bridge") {
            return .other
        }
        return .other
    }

    static func mediumFromPath(_ path: NWPath) -> NetworkLinkMedium {
        guard path.status == .satisfied || path.status == .requiresConnection else {
            return .none
        }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .other }
        if path.availableInterfaces.contains(where: { $0.type == .wiredEthernet }) {
            return .wired
        }
        if path.availableInterfaces.contains(where: { $0.type == .wifi }) {
            return .wifi
        }
        return path.availableInterfaces.isEmpty ? .none : .other
    }

    /// 用户 VPN / TUN：以**主接口**为准。系统常驻空闲 `utun*` 不算。
    static func isTunnelPrimary(_ primary: String?) -> Bool {
        guard let primary else { return false }
        return isTunnelInterfaceName(primary)
    }

    static func isTunnelInterfaceName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utun")
            || lower.hasPrefix("ipsec")
            || lower.hasPrefix("ppp")
            || lower.hasPrefix("tun")
            || lower.hasPrefix("tap")
            || lower.hasPrefix("wg")
    }

    /// Clash 等「系统代理」模式：HTTP/HTTPS/SOCKS 任一开启即视作 VPN 态。
    static func isSystemProxyActive() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "Ridge.NetworkLink.Proxy" as CFString, nil, nil),
              let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/Proxies" as CFString) as? [String: Any]
        else { return false }
        func enabled(_ key: String) -> Bool {
            if let n = info[key] as? NSNumber { return n.intValue != 0 }
            if let i = info[key] as? Int { return i != 0 }
            return false
        }
        return enabled("HTTPEnable")
            || enabled("HTTPSEnable")
            || enabled("SOCKSEnable")
            || enabled("ProxyAutoConfigEnable")
    }

    static func currentWiFiSSID() -> String? {
        #if canImport(CoreWLAN)
        // Sonoma+：未授定位服务时恒为 nil（见 `NetworkLinkLocationAccess`）。
        return CWWiFiClient.shared().interface()?.ssid()
        #else
        return nil
        #endif
    }

    /// 空串 / 过长 / 像 MAC 的串不当作展示名。
    static func sanitizedSSID(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.count > 32 { s = String(s.prefix(32)) }
        let hexMac = s
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        if hexMac.count == 12, hexMac.unicodeScalars.allSatisfy({ CharacterSet.hexadecimalDigits.contains($0) }) {
            return nil
        }
        return s
    }
}

private extension CharacterSet {
    static let hexadecimalDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
}
