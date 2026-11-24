import Foundation

/// 隔空投送文件接收完成 tip 载荷。
struct AirDropReceiveNotice: Hashable, Identifiable {
    let id: String
    let path: String
    let fileName: String
}

enum AirDropReceiveClickAction: String, CaseIterable, Identifiable {
    case openWithDefaultApp
    case revealInFinder

    var id: String { rawValue }
}

/// 纯函数：是否把 Downloads 里新文件当成 AirDrop 接收（可单测）。
enum AirDropReceiveAttribution {
    /// quarantine / 来源里视为隔空投送的 agent。
    static let airDropAgentMarkers: [String] = [
        "com.apple.sharingd",
        "com.apple.AirDrop",
        "sharingd",
        "AirDrop"
    ]

    /// 明确是浏览器下载时排除（交给下载常驻）。
    static let browserAgentMarkers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.operasoftware.Opera"
    ]

    /// 须有正向 AirDrop 信号；禁止把普通 Downloads 新文件都当 tip。
    static func isLikelyAirDropReceive(
        fileName: String,
        quarantineAgentBundleID: String?,
        whereFroms: [String]
    ) -> Bool {
        if DownloadPathLogic.matchedTempSuffix(fileName) != nil {
            return false
        }
        let stripped = DownloadPathLogic.matchedTempSuffix(fileName)
            .map { String(fileName.dropLast($0.count)) } ?? fileName
        if DownloadPathLogic.isUnconfirmedTempBase(stripped) {
            return false
        }

        if let agent = quarantineAgentBundleID, !agent.isEmpty {
            if matchesAnyMarker(agent, markers: browserAgentMarkers) {
                return false
            }
            if matchesAnyMarker(agent, markers: airDropAgentMarkers) {
                return true
            }
        }

        for source in whereFroms {
            let lower = source.lowercased()
            if lower.contains("airdrop") || source.contains("隔空") {
                return true
            }
        }
        return false
    }

    private static func matchesAnyMarker(_ value: String, markers: [String]) -> Bool {
        let lower = value.lowercased()
        return markers.contains { marker in
            lower == marker.lowercased() || lower.contains(marker.lowercased())
        }
    }
}
