import Foundation

/// 解析 `system_profiler SPBluetoothDataType -json`：与系统「我的设备」同源。
/// 用于补全 IOBluetooth / BLE 读不到的 `device_batteryLevel*`，并带上无电量但仍已连接的设备。
enum BatterySystemProfilerProbe {
    struct Snapshot: Equatable {
        var address: String
        var name: String
        var kind: BatteryDeviceKind
        var percent: Int?
        var leftPercent: Int?
        var rightPercent: Int?
        var casePercent: Int?
    }

    private static var cache: (at: Date, items: [Snapshot])?
    private static let cacheTTL: TimeInterval = 8

    static func connectedDevices(force: Bool = false) -> [Snapshot] {
        if !force, let cache, Date().timeIntervalSince(cache.at) < cacheTTL {
            return cache.items
        }
        let items = fetch()
        cache = (Date(), items)
        return items
    }

    private static func fetch() -> [Snapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLog.warn("Battery", "system_profiler 启动失败", ["error": error.localizedDescription])
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !data.isEmpty else {
            AppLog.debug("Battery", "system_profiler 无输出", ["status": process.terminationStatus])
            return []
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["SPBluetoothDataType"] as? [[String: Any]],
              let first = list.first
        else {
            AppLog.debug("Battery", "system_profiler JSON 解析失败")
            return []
        }

        let connected = extractConnectedEntries(from: first)
        if connected.isEmpty {
            AppLog.debug("Battery", "system_profiler 无已连接条目", [
                "topKeys": first.keys.sorted().joined(separator: ",")
            ])
            return []
        }

        var snaps: [Snapshot] = []
        for entry in connected {
            guard let (name, info) = entry.first, let info = info as? [String: Any] else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let address = normalizeAddress(info["device_address"] as? String ?? "")
            let left = parsePercent(info["device_batteryLevelLeft"])
            let right = parsePercent(info["device_batteryLevelRight"])
            let casePct = parsePercent(info["device_batteryLevelCase"])
            let main = parsePercent(info["device_batteryLevelMain"])
            let buds = [left, right].compactMap { $0 }
            let percent: Int?
            if !buds.isEmpty {
                percent = buds.min()
            } else {
                percent = main ?? casePct
            }
            let minor = (info["device_minorType"] as? String) ?? ""
            let kind = classify(name: trimmed, minorType: minor, hasSplitBuds: !buds.isEmpty)
            snaps.append(
                Snapshot(
                    address: address.isEmpty ? "sp.\(trimmed.lowercased())" : address,
                    name: trimmed,
                    kind: kind,
                    percent: percent,
                    leftPercent: left,
                    rightPercent: right,
                    casePercent: casePct
                )
            )
        }
        AppLog.debug("Battery", "system_profiler 已连接外设", [
            "count": snaps.count,
            "withPercent": snaps.filter { $0.percent != nil }.count,
            "names": snaps.map(\.name).joined(separator: ",")
        ])
        return snaps
    }

    /// 兼容 `device_connected` 为数组，或个别系统版本下嵌在其它键里的形态。
    private static func extractConnectedEntries(from root: [String: Any]) -> [[String: Any]] {
        if let connected = root["device_connected"] as? [[String: Any]] {
            return connected
        }
        // 少数版本写成单层字典：{ "Name": { ... }, ... }
        if let connected = root["device_connected"] as? [String: Any] {
            return connected.compactMap { key, value in
                guard let info = value as? [String: Any] else { return nil }
                return [key: info]
            }
        }
        return []
    }

    private static func classify(name: String, minorType: String, hasSplitBuds: Bool) -> BatteryDeviceKind {
        let minor = minorType.lowercased()
        if hasSplitBuds || minor.contains("headphone") { return .headphones }
        if minor.contains("headset") { return .headset }
        if minor.contains("keyboard") { return .keyboard }
        if minor.contains("mouse") { return .mouse }
        if minor.contains("trackpad") { return .trackpad }
        if minor.contains("gamepad") || minor.contains("controller") { return .gamepad }
        return BatteryBluetoothProbe.classifyPublic(name: name, hasSplitBuds: hasSplitBuds)
    }

    private static func parsePercent(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        if let n = raw as? Int { return (1...100).contains(n) ? n : nil }
        if let s = raw as? String {
            let digits = s.filter(\.isNumber)
            guard let n = Int(digits), (1...100).contains(n) else { return nil }
            return n
        }
        return nil
    }

    private static func normalizeAddress(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: ":", with: "-")
    }
}
