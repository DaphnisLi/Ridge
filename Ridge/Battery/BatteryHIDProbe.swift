import Foundation
import IOKit.hid

/// 从 IOHID 读 `BatteryPercent`（妙控键鼠等常见；第三方 BLE 键盘往往没有此键）。
enum BatteryHIDProbe {
    struct Snapshot: Equatable {
        var name: String
        var percent: Int
        var kind: BatteryDeviceKind
        var transport: String
    }

    static func connectedDevices() -> [Snapshot] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let open = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard open == kIOReturnSuccess else {
            AppLog.debug("Battery", "IOHIDManager 打开失败", ["kr": Int(open)])
            return []
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var list: [Snapshot] = []
        var seen = Set<String>()

        for device in set {
            let name = ((IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }

            let percent: Int?
            if let n = IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString) as? NSNumber {
                percent = n.intValue
            } else if let i = IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString) as? Int {
                percent = i
            } else {
                percent = nil
            }
            guard let percent, percent > 0, percent <= 100 else { continue }

            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
            let kind = classify(name: name, device: device)
            seen.insert(key)
            list.append(Snapshot(name: name, percent: percent, kind: kind, transport: transport))
        }

        if !list.isEmpty {
            AppLog.debug("Battery", "IOHID 电量命中", ["count": list.count])
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func classify(name: String, device: IOHIDDevice) -> BatteryDeviceKind {
        if isKeyboard(device) { return .keyboard }
        if isPointer(device) {
            let hay = name.lowercased()
            if hay.contains("trackpad") || hay.contains("触控板") { return .trackpad }
            return .mouse
        }
        return BatteryBluetoothProbe.classifyPublic(name: name, hasSplitBuds: false)
    }

    private static func isKeyboard(_ device: IOHIDDevice) -> Bool {
        usagePairs(device).contains { $0.page == 0x01 && ($0.usage == 0x06 || $0.usage == 0x07) }
    }

    private static func isPointer(_ device: IOHIDDevice) -> Bool {
        usagePairs(device).contains { $0.page == 0x01 && ($0.usage == 0x02 || $0.usage == 0x01) }
    }

    private static func usagePairs(_ device: IOHIDDevice) -> [(page: Int, usage: Int)] {
        guard let raw = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { dict in
            guard let page = dict[kIOHIDDeviceUsagePageKey] as? Int,
                  let usage = dict[kIOHIDDeviceUsageKey] as? Int
            else { return nil }
            return (page, usage)
        }
    }
}
