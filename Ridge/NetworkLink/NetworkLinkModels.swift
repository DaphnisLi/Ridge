import Foundation

/// 主路径介质（VPN 另计）。
enum NetworkLinkMedium: String, Equatable {
    case none
    case wifi
    case wired
    case other
}

/// 网络 / VPN 瞬时 tip 五类。
enum NetworkLinkTipKind: String, Equatable, CaseIterable {
    case wifiConnected
    case wiredConnected
    case vpnConnected
    case wifiDisconnected
    case vpnDisconnected
}

struct NetworkLinkSnapshot: Equatable {
    var medium: NetworkLinkMedium
    var vpnActive: Bool
    /// 仅 `medium == .wifi` 时有意义；读不到或不适展示则为 nil。
    var wifiSSID: String?

    init(
        medium: NetworkLinkMedium,
        vpnActive: Bool,
        wifiSSID: String? = nil
    ) {
        self.medium = medium
        self.vpnActive = vpnActive
        self.wifiSSID = wifiSSID
    }
}

/// 岛上 tip 载荷（左图标+名称 / 右延迟或「断开」+状态点）。
struct NetworkLinkNotice: Identifiable, Hashable {
    let id: String
    let kind: NetworkLinkTipKind
    /// 左翼主名称：SSID /「以太网」/「离线」/ VPN 名。
    let title: String
    /// 右翼：`18ms` / `断开`；可空只留点。
    let detail: String?
    /// 原始 SSID（日志 / 兼容）；展示用 `title`。
    let ssid: String?
    /// 网关往返（毫秒）；展示已编入 `detail`。
    let latencyMs: Int?

    init(
        id: String,
        kind: NetworkLinkTipKind,
        title: String,
        detail: String? = nil,
        ssid: String? = nil,
        latencyMs: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.ssid = ssid
        self.latencyMs = latencyMs
    }
}
