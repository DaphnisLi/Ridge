import CoreBluetooth
import Foundation
import IOKit.hid

/// 从 IOHID 读 `BatteryPercent`（妙控键鼠等常见；第三方 BLE 键盘往往没有此键）。
///
/// **禁止** `IOHIDManagerSetDeviceMatching(nil)`：会打开全部键盘类 HID，
/// 在较新的 macOS 上会顺带弹出「输入监控」授权（与蓝牙外设电量无关）。
enum BatteryHIDProbe {
    struct Snapshot: Equatable {
        var name: String
        var percent: Int
        var kind: BatteryDeviceKind
        var transport: String
    }

    /// HID Battery System 用法页；只枚举带电池语义的设备，避免扫到键盘输入流。
    private static let batterySystemUsagePage = 0x85

    /// 蓝牙系统对话框未决时不要碰 HID，以免与「输入监控」叠弹。
    @MainActor
    static var shouldProbeNow: Bool {
        switch CBManager.authorization {
        case .notDetermined:
            return false
        default:
            return true
        }
    }

    @MainActor
    static func connectedDevicesIfAllowed() -> [Snapshot] {
        guard shouldProbeNow else {
            AppLog.debug("Battery", "跳过 IOHID 电量探测：蓝牙权限未决，避免触发输入监控")
            return []
        }
        return connectedDevices()
    }

    static func connectedDevices() -> [Snapshot] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // 仅匹配 Battery System（0x85），勿 matching:nil。
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: batterySystemUsagePage
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
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
