import Foundation

/// 网络 tip 合并：断开先入短窗；窗内若出现同族连接或主路径换介质，丢弃断开，只出连接 tip。
struct NetworkLinkTipPolicy {
    /// 断开 debounce 窗（秒）。
    static let coalesceWindow: TimeInterval = 1.25

    private(set) var last: NetworkLinkSnapshot?
    private var pendingWifiDisconnectAt: Date?
    private var pendingVPNDisconnectAt: Date?

    mutating func reset() {
        last = nil
        pendingWifiDisconnectAt = nil
        pendingVPNDisconnectAt = nil
    }

    /// 摄入新快照；返回此刻应立刻投递的 tip（含已到期的 pending 断开）。
    mutating func ingest(_ next: NetworkLinkSnapshot, now: Date = Date()) -> [NetworkLinkTipKind] {
        var out = flushPending(now: now)

        guard let prev = last else {
            last = next
            return out
        }

        // —— VPN ——
        if !prev.vpnActive, next.vpnActive {
            pendingVPNDisconnectAt = nil
            out.append(.vpnConnected)
        } else if prev.vpnActive, !next.vpnActive {
            pendingVPNDisconnectAt = now
        }

        // —— 主路径介质 ——
        if prev.medium != next.medium {
            switch next.medium {
            case .wifi:
                pendingWifiDisconnectAt = nil
                out.append(.wifiConnected)
            case .wired:
                // Wi‑Fi→有线 / 无网→有线：只 tip 有线；取消待发的 Wi‑Fi 断开。
                pendingWifiDisconnectAt = nil
                out.append(.wiredConnected)
            case .none, .other:
                // 仅从 Wi‑Fi 掉下才排「Wi‑Fi 已断开」；有线纯断开不单独 tip。
                if prev.medium == .wifi {
                    pendingWifiDisconnectAt = now
                }
            }
        } else if next.medium == .wifi,
                  Self.ssidChanged(from: prev.wifiSSID, to: next.wifiSSID)
        {
            // 同介质换 SSID（未观察到中间 none）：仍 tip 已连接。
            pendingWifiDisconnectAt = nil
            out.append(.wifiConnected)
        }

        last = next
        return out
    }

    /// 定时滴答：仅冲刷到期的断开 tip。
    mutating func tick(now: Date = Date()) -> [NetworkLinkTipKind] {
        flushPending(now: now)
    }

    // MARK: - Private

    private mutating func flushPending(now: Date) -> [NetworkLinkTipKind] {
        var out: [NetworkLinkTipKind] = []
        if let at = pendingWifiDisconnectAt,
           now.timeIntervalSince(at) >= Self.coalesceWindow
        {
            pendingWifiDisconnectAt = nil
            out.append(.wifiDisconnected)
        }
        if let at = pendingVPNDisconnectAt,
           now.timeIntervalSince(at) >= Self.coalesceWindow
        {
            pendingVPNDisconnectAt = nil
            out.append(.vpnDisconnected)
        }
        return out
    }

    private static func ssidChanged(from old: String?, to new: String?) -> Bool {
        let a = (old ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let b = (new ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return false }
        return a != b
    }
}
