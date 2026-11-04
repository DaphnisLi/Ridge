import Foundation
import IOBluetooth
import ObjectiveC

/// 枚举已连接蓝牙外设（IOBluetooth）。
/// Apple / AirPods 用电量私有字段；第三方键鼠常为 0，需再合并 BLE Battery Service / IOHID。
enum BatteryBluetoothProbe {
    struct Snapshot: Equatable {
        var address: String
        var name: String
        var kind: BatteryDeviceKind
        /// 私有 API 读到的电量；0 / 缺失表示不可用。
        var percent: Int?
        var isCharging: Bool
        var leftPercent: Int?
        var rightPercent: Int?
        var casePercent: Int?
        /// AirPods：1 关闭 / 2 降噪 / 3 通透 / 4 自适应；不支持则为 nil。
        var listeningMode: BatteryListeningMode?
    }

    /// 所有已连接设备（含尚无有效电量者），供上层与 BLE/HID 合并。
    static func connectedDevices() -> [Snapshot] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var list: [Snapshot] = []
        var skippedNoName = 0
        for device in paired where device.isConnected() {
            let name = (device.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                skippedNoName += 1
                continue
            }
            // 个别经典蓝牙耳机 addressString 可能为空，仍须展示（如部分 Sony XM 系列）。
            let rawAddr = normalizeAddress(device.addressString ?? "")
            let addr = rawAddr.isEmpty ? "bt.\(name.lowercased())" : rawAddr
            let left = intPercent(callUInt8(device, "batteryPercentLeft"))
            let right = intPercent(callUInt8(device, "batteryPercentRight"))
            let single = intPercent(callUInt8(device, "batteryPercentSingle"))
            let combined = intPercent(callUInt8(device, "batteryPercentCombined"))
            let casePct = intPercent(callUInt8(device, "batteryPercentCase"))
            let headset = intPercent(callUInt8(device, "headsetBattery"))
            let buds = [left, right].compactMap { $0 }
            let percent: Int?
            if !buds.isEmpty {
                percent = buds.min()
            } else {
                percent = single ?? combined ?? headset ?? casePct
            }
            let kind = classifyPublic(name: name, hasSplitBuds: !buds.isEmpty)
            let charging = callBool(device, "isCharging")
                || callBool(device, "isBatteryCharging")
            // 本机记录 → 同名 paired 别名。
            let listening = readListeningMode(device)
                ?? readListeningModeFromPairedAlias(named: name, excludingAddress: addr)
            list.append(
                Snapshot(
                    address: addr,
                    name: name,
                    kind: kind,
                    percent: percent,
                    isCharging: charging,
                    leftPercent: left,
                    rightPercent: right,
                    casePercent: casePct,
                    listeningMode: listening
                )
            )
        }
        AppLog.debug("Battery", "IOBluetooth 已连接外设", [
            "count": list.count,
            "withPercent": list.filter { $0.percent != nil }.count,
            "withListening": list.filter { $0.listeningMode != nil }.count,
            "skippedNoName": skippedNoName,
            "names": list.map(\.name).joined(separator: ",")
        ])
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Classify

    static func classifyPublic(name: String, hasSplitBuds: Bool) -> BatteryDeviceKind {
        let hay = name.lowercased()
        if hasSplitBuds
            || hay.contains("airpods")
            || hay.contains("buds")
            || hay.contains("earbud")
        {
            return .headphones
        }
        if hay.contains("keyboard")
            || hay.contains("键盘")
            || hay.contains("magic keyboard")
            || hay.contains("keychron")
            || hay.contains("nuphy")
            || hay.contains("aula")
            || hay.contains("gmmk")
            || hay.contains("r75")
            || hay.contains("f87")
            || hay.contains("ikb")
            || hay.contains("anne pro")
            || hay.hasSuffix("kb")
        {
            return .keyboard
        }
        if hay.contains("mouse") || hay.contains("鼠标") || hay.contains("magic mouse") {
            return .mouse
        }
        if hay.contains("trackpad") || hay.contains("触控板") || hay.contains("magic trackpad") {
            return .trackpad
        }
        if hay.contains("dualsense") || hay.contains("xbox") || hay.contains("gamepad")
            || hay.contains("controller") || hay.contains("手柄")
        {
            return .gamepad
        }
        if hay.contains("headset") || hay.contains("wh-") || hay.contains("xm5")
            || hay.contains("xm4") || hay.contains("降噪")
        {
            return .headset
        }
        if hay.contains("headphone") || hay.contains("耳机") {
            return .headphones
        }
        return .other
    }

    // MARK: - Listening mode

    /// 同名其它已连接 paired 设备上再试一次聆听模式（AirPods 偶发双记录）。
    /// 未连接别名不探测，避免把盒内/幽灵记录当成在线。
    private static func readListeningModeFromPairedAlias(
        named name: String,
        excludingAddress: String
    ) -> BatteryListeningMode? {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for device in paired where device.isConnected() {
            let otherName = (device.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard otherName == key else { continue }
            let otherAddr = normalizeAddress(device.addressString ?? "")
            if !excludingAddress.isEmpty, otherAddr == excludingAddress { continue }
            if let mode = readListeningMode(device) {
                AppLog.info("Battery", "聆听模式来自同名 paired 别名", [
                    "name": name,
                    "alias": otherAddr,
                    "mode": mode.rawValue
                ])
                return mode
            }
        }
        return nil
    }

    /// IOBluetooth 私有：`listeningMode` 1 关闭 / 2 降噪 / 3 通透 / 4 自适应。
    /// 不先依赖 isANCSupported（ObjC BOOL 易读错）；有有效 raw 就认。
    private static func readListeningMode(_ device: IOBluetoothDevice) -> BatteryListeningMode? {
        let name = device.name ?? ""
        let objcByte = BatteryListeningModeBridge.listeningMode(for: device)
        let raw = objcByte > 0 ? objcByte : readListeningModeRaw(device)
        let configsByte = BatteryListeningModeBridge.listeningModeConfigs(for: device)
        let configs = configsByte > 0 ? configsByte : readUIntByte(device, "listeningModeConfigs")
        let supportsANC = BatteryListeningModeBridge.isANCSupported(for: device)
            || callObjCBool(device, "isANCSupported")
        let supportsTransparency = BatteryListeningModeBridge.isTransparencySupported(for: device)
            || callObjCBool(device, "isTransparencySupported")
        let advanced = callObjCBool(device, "isAdvancedAppleAudioDevice")
        let looksAppleAudio = advanced
            || supportsANC
            || supportsTransparency
            || name.localizedCaseInsensitiveContains("airpods")
            || name.localizedCaseInsensitiveContains("beats")

        let mode = Self.mapListeningMode(raw)

        if looksAppleAudio {
            let inEar = callObjCBool(device, "inEar")
            AppLog.info("Battery", "聆听模式探测", [
                "name": name,
                "objcByte": Int(objcByte),
                "raw": raw.map { Int($0) } ?? -1,
                "configs": configs.map { Int($0) } ?? Int(configsByte),
                "anc": supportsANC,
                "transparency": supportsTransparency,
                "advanced": advanced,
                "inEar": inEar,
                "mode": mode?.rawValue ?? "nil"
            ])
            appendListeningDiag([
                "name=\(name)",
                "connected=\(device.isConnected())",
                "objcByte=\(objcByte)",
                "raw=\(raw.map(String.init) ?? "nil")",
                "configs=\(configs.map(String.init) ?? String(configsByte))",
                "anc=\(supportsANC)",
                "transparency=\(supportsTransparency)",
                "advanced=\(advanced)",
                "inEar=\(inEar)",
                "mode=\(mode?.rawValue ?? "nil")"
            ].joined(separator: " "))
        }

        return mode
    }

    private static func mapListeningMode(_ raw: UInt8?) -> BatteryListeningMode? {
        guard let raw else { return nil }
        switch raw {
        case 1: return .off
        case 2: return .noiseCancellation
        case 3: return .transparency
        case 4: return .adaptive
        default: return nil
        }
    }

    private static func readListeningModeRaw(_ device: IOBluetoothDevice) -> UInt8? {
        // 先向系统要一次最新属性（无此方法则跳过）。
        let refresh = NSSelectorFromString("updateFromServer")
        if device.responds(to: refresh) {
            _ = device.perform(refresh)
        }

        // 1) 按 UInt64 取回再截低 8 位（unsigned char 属性在 arm64 上更稳）。
        if let raw = readUIntByte(device, "listeningMode"), raw > 0 {
            return raw
        }
        // 2) KVC
        if device.responds(to: NSSelectorFromString("listeningMode")),
           let number = device.value(forKey: "listeningMode") as? NSNumber
        {
            let raw = number.uint8Value
            if raw > 0 { return raw }
        }
        // 3) Bluetooth DeviceCache plist（旧系统常见；新系统可能无此键）。
        if let fromPlist = readListeningModeFromBluetoothPlist(device), fromPlist > 0 {
            return fromPlist
        }
        return nil
    }

    /// `/Library/Preferences/com.apple.Bluetooth.plist` → DeviceCache → ListeningMode
    private static func readListeningModeFromBluetoothPlist(_ device: IOBluetoothDevice) -> UInt8? {
        guard let address = device.addressString?.lowercased(), !address.isEmpty else { return nil }
        let candidates = [
            "/Library/Preferences/com.apple.Bluetooth.plist",
            NSHomeDirectory() + "/Library/Preferences/com.apple.Bluetooth.plist"
        ]
        for path in candidates {
            guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
                  let cache = dict["DeviceCache"] as? [String: Any]
            else { continue }
            // 地址格式可能是 aa-bb-… 或 aa:bb:…
            let keys = [
                address,
                address.replacingOccurrences(of: "-", with: ":"),
                address.replacingOccurrences(of: ":", with: "-")
            ]
            for key in keys {
                guard let entry = cache[key] as? [String: Any] else { continue }
                if let n = entry["ListeningMode"] as? NSNumber {
                    return n.uint8Value
                }
                if let s = entry["ListeningMode"] as? String, let n = UInt8(s) {
                    return n
                }
            }
        }
        return nil
    }

    /// 探针结果双写：App Support（沙盒可读）+ 仓库 build（开发机可读）。
    private static func appendListeningDiag(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        let data = Data(text.utf8)
        var urls: [URL] = [
            URL(fileURLWithPath: "/Users/daphnis/project/Ridge/build/battery-listening.log")
        ]
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = support.appendingPathComponent("Ridge", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            urls.append(dir.appendingPathComponent("battery-listening.log"))
        }
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url)
            {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Runtime helpers

    private static func normalizeAddress(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: ":", with: "-")
    }

    /// 私有字段：0 视为无效（第三方设备常见占位）。
    private static func intPercent(_ raw: UInt8?) -> Int? {
        guard let raw, raw > 0, raw <= 100 else { return nil }
        return Int(raw)
    }

    private static func readUIntByte(_ object: AnyObject, _ selectorName: String) -> UInt8? {
        let sel = NSSelectorFromString(selectorName)
        guard object.responds(to: sel) else { return nil }
        let cls: AnyClass? = object_getClass(object)
        guard let cls,
              let imp = class_getMethodImplementation(cls, sel)
        else { return nil }
        // 用宽整型接返回值，再取低字节，避免 unsigned char ABI 截断问题。
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt64
        let wide = unsafeBitCast(imp, to: Fn.self)(object, sel)
        return UInt8(truncatingIfNeeded: wide)
    }

    private static func callUInt8(_ object: AnyObject, _ selectorName: String) -> UInt8? {
        readUIntByte(object, selectorName)
    }

    /// ObjC `BOOL` 是 signed char，不能按 Swift `Bool` 调。
    private static func callObjCBool(_ object: AnyObject, _ selectorName: String) -> Bool {
        let sel = NSSelectorFromString(selectorName)
        guard object.responds(to: sel) else { return false }
        guard let imp = class_getMethodImplementation(object_getClass(object), sel) else {
            return false
        }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Int8
        return unsafeBitCast(imp, to: Fn.self)(object, sel) != 0
    }

    private static func callBool(_ object: AnyObject, _ selectorName: String) -> Bool {
        callObjCBool(object, selectorName)
    }
}
