import XCTest
@testable import Ridge

/// 网络 tip 合并：切换抑制中间断开；纯断开才 tip 断开。
final class NetworkLinkTipPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func test_seedEmitsNothing() {
        var policy = NetworkLinkTipPolicy()
        let tips = policy.ingest(
            .init(medium: .wifi, vpnActive: false, wifiSSID: "A"),
            now: t0
        )
        XCTAssertTrue(tips.isEmpty)
    }

    func test_wifiToWired_onlyWiredConnected() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wifi, vpnActive: false, wifiSSID: "A"), now: t0)
        let tips = policy.ingest(
            .init(medium: .wired, vpnActive: false, wifiSSID: nil),
            now: t0.addingTimeInterval(0.1)
        )
        XCTAssertEqual(tips, [.wiredConnected])
        // 短窗过后也不应冒出 Wi‑Fi 断开。
        let later = policy.tick(now: t0.addingTimeInterval(NetworkLinkTipPolicy.coalesceWindow + 0.5))
        XCTAssertTrue(later.isEmpty)
    }

    func test_wiredToWifi_onlyWifiConnected() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wired, vpnActive: false, wifiSSID: nil), now: t0)
        let tips = policy.ingest(
            .init(medium: .wifi, vpnActive: false, wifiSSID: "B"),
            now: t0.addingTimeInterval(0.1)
        )
        XCTAssertEqual(tips, [.wifiConnected])
    }

    func test_wifiRoam_disconnectThenConnect_suppressesDisconnect() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wifi, vpnActive: false, wifiSSID: "A"), now: t0)
        let mid = policy.ingest(
            .init(medium: .none, vpnActive: false, wifiSSID: nil),
            now: t0.addingTimeInterval(0.1)
        )
        XCTAssertTrue(mid.isEmpty, "断开只入 pending，不立刻 tip")
        let end = policy.ingest(
            .init(medium: .wifi, vpnActive: false, wifiSSID: "B"),
            now: t0.addingTimeInterval(0.4)
        )
        XCTAssertEqual(end, [.wifiConnected])
        let later = policy.tick(now: t0.addingTimeInterval(NetworkLinkTipPolicy.coalesceWindow + 1))
        XCTAssertTrue(later.isEmpty)
    }

    func test_pureWifiDisconnect_emitsAfterWindow() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wifi, vpnActive: false, wifiSSID: "A"), now: t0)
        _ = policy.ingest(
            .init(medium: .none, vpnActive: false, wifiSSID: nil),
            now: t0.addingTimeInterval(0.1)
        )
        let early = policy.tick(now: t0.addingTimeInterval(0.5))
        XCTAssertTrue(early.isEmpty)
        let flushed = policy.tick(
            now: t0.addingTimeInterval(0.1 + NetworkLinkTipPolicy.coalesceWindow + 0.05)
        )
        XCTAssertEqual(flushed, [.wifiDisconnected])
    }

    func test_vpnSwap_suppressesDisconnect() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wifi, vpnActive: true, wifiSSID: "A"), now: t0)
        let mid = policy.ingest(
            .init(medium: .wifi, vpnActive: false, wifiSSID: "A"),
            now: t0.addingTimeInterval(0.1)
        )
        XCTAssertTrue(mid.isEmpty)
        let end = policy.ingest(
            .init(medium: .wifi, vpnActive: true, wifiSSID: "A"),
            now: t0.addingTimeInterval(0.5)
        )
        XCTAssertEqual(end, [.vpnConnected])
        let later = policy.tick(now: t0.addingTimeInterval(NetworkLinkTipPolicy.coalesceWindow + 1))
        XCTAssertTrue(later.isEmpty)
    }

    func test_pureVPNDisconnect_emitsAfterWindow() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wifi, vpnActive: true, wifiSSID: "A"), now: t0)
        _ = policy.ingest(
            .init(medium: .wifi, vpnActive: false, wifiSSID: "A"),
            now: t0.addingTimeInterval(0.1)
        )
        let flushed = policy.tick(
            now: t0.addingTimeInterval(0.1 + NetworkLinkTipPolicy.coalesceWindow + 0.05)
        )
        XCTAssertEqual(flushed, [.vpnDisconnected])
    }

    func test_wiredDrop_noDisconnectTip() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wired, vpnActive: false, wifiSSID: nil), now: t0)
        let mid = policy.ingest(
            .init(medium: .none, vpnActive: false, wifiSSID: nil),
            now: t0.addingTimeInterval(0.1)
        )
        XCTAssertTrue(mid.isEmpty)
        let later = policy.tick(now: t0.addingTimeInterval(NetworkLinkTipPolicy.coalesceWindow + 1))
        XCTAssertTrue(later.isEmpty, "有线纯断开不单独 tip")
    }

    func test_ssidChangeSameMedium_emitsWifiConnected() {
        var policy = NetworkLinkTipPolicy()
        _ = policy.ingest(.init(medium: .wifi, vpnActive: false, wifiSSID: "A"), now: t0)
        let tips = policy.ingest(
            .init(medium: .wifi, vpnActive: false, wifiSSID: "B"),
            now: t0.addingTimeInterval(0.2)
        )
        XCTAssertEqual(tips, [.wifiConnected])
    }

    func test_sanitizedSSID_rejectsMACLike() {
        XCTAssertNil(NetworkLinkMonitor.sanitizedSSID("aa:bb:cc:dd:ee:ff"))
        XCTAssertEqual(NetworkLinkMonitor.sanitizedSSID("  Cafe  "), "Cafe")
        XCTAssertNil(NetworkLinkMonitor.sanitizedSSID("   "))
    }

    func test_tunnelPrimary_ignoresIdleUtunUnlessPrimary() {
        XCTAssertTrue(NetworkLinkMonitor.isTunnelInterfaceName("utun4"))
        XCTAssertTrue(NetworkLinkMonitor.isTunnelInterfaceName("ipsec0"))
        XCTAssertFalse(NetworkLinkMonitor.isTunnelInterfaceName("en0"))
        XCTAssertTrue(NetworkLinkMonitor.isTunnelPrimary("utun4"))
        XCTAssertFalse(NetworkLinkMonitor.isTunnelPrimary("en0"))
        XCTAssertFalse(NetworkLinkMonitor.isTunnelPrimary(nil))
    }

    func test_formatLatency() {
        XCTAssertEqual(NetworkLinkMetrics.formatLatency(18), "18ms")
        XCTAssertEqual(NetworkLinkMetrics.formatLatency(1), "1ms")
        XCTAssertNil(NetworkLinkMetrics.formatLatency(nil))
        XCTAssertNil(NetworkLinkMetrics.formatLatency(0))
    }

    func test_latencyTone_warnsWhenElevated() {
        XCTAssertEqual(NetworkLinkMetrics.latencyTone(ms: 18), .good)
        XCTAssertEqual(NetworkLinkMetrics.latencyTone(ms: 99), .good)
        XCTAssertEqual(NetworkLinkMetrics.latencyTone(ms: 100), .elevated)
        XCTAssertEqual(NetworkLinkMetrics.latencyTone(ms: 200), .elevated)
        XCTAssertEqual(NetworkLinkMetrics.latencyTone(ms: nil), .unknown)
        XCTAssertEqual(NetworkLinkMetrics.latencyWarningMs, 100)
    }

    func test_wifiDisconnect_enrichUsesRememberedSSID() async {
        let snap = NetworkLinkSnapshot(medium: .none, vpnActive: false, wifiSSID: nil)
        let enrichment = await NetworkLinkMetrics.enrich(
            kind: .wifiDisconnected,
            snap: snap,
            lastKnownWifiSSID: "AirNet"
        )
        XCTAssertEqual(enrichment.title, "AirNet")
        XCTAssertEqual(enrichment.ssid, "AirNet")
        XCTAssertEqual(enrichment.detail, L10n.NetworkLink.disconnectedBadge)

        let fallback = await NetworkLinkMetrics.enrich(
            kind: .wifiDisconnected,
            snap: snap,
            lastKnownWifiSSID: nil
        )
        XCTAssertEqual(fallback.title, L10n.NetworkLink.offlineTitle)
    }
}
