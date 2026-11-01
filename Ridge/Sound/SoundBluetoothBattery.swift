import Foundation
import IOBluetooth
import ObjectiveC

/// 蓝牙耳机 / 外设电量（IOBluetooth 私有属性，与系统设置同源）。
enum SoundBluetoothBattery {
    /// 按音频设备 UID（如 `EC-73-79-07-02-34:output`）查电量 0…100。
    /// 需要 Info.plist 含 `NSBluetoothAlwaysUsageDescription`，否则系统会直接终止进程。
    static func percent(forAudioDeviceUID uid: String) -> Int? {
        guard let address = bluetoothAddress(fromAudioUID: uid) else { return nil }
        guard let device = connectedDevice(address: address) else { return nil }
        return displayPercent(for: device)
    }

    /// 规范化后的蓝牙地址，如 `ec-73-79-07-02-34`。
    static func bluetoothAddress(fromAudioUID uid: String) -> String? {
        let base = uid.split(separator: ":").first.map(String.init) ?? uid
        let normalized = base
            .lowercased()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        // 粗略校验：至少含 5 段十六进制（经典蓝牙地址）。
        let parts = normalized.split(separator: "-")
        guard parts.count >= 6, parts.prefix(6).allSatisfy({ $0.count == 2 }) else {
            return nil
        }
        return parts.prefix(6).joined(separator: "-")
    }

    // MARK: - Private

    private static func connectedDevice(address: String) -> IOBluetoothDevice? {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.first { device in
            guard device.isConnected() else { return false }
            let addr = (device.addressString ?? "")
                .lowercased()
                .replacingOccurrences(of: ":", with: "-")
            return addr == address
        }
    }

    private static func displayPercent(for device: IOBluetoothDevice) -> Int? {
        let left = intPercent(callUInt8(device, "batteryPercentLeft"))
        let right = intPercent(callUInt8(device, "batteryPercentRight"))
        let single = intPercent(callUInt8(device, "batteryPercentSingle"))
        let combined = intPercent(callUInt8(device, "batteryPercentCombined"))
        let casePct = intPercent(callUInt8(device, "batteryPercentCase"))
        let headset = intPercent(callUInt8(device, "headsetBattery"))

        let buds = [left, right].compactMap { $0 }
        if !buds.isEmpty {
            // 与菜单栏一致：取左右耳较低值，避免虚高。
            return buds.min()
        }
        if let single { return single }
        if let combined { return combined }
        if let headset { return headset }
        if let casePct { return casePct }
        return nil
    }

    private static func intPercent(_ raw: UInt8?) -> Int? {
        guard let raw, raw > 0, raw <= 100 else { return nil }
        return Int(raw)
    }

    private static func callUInt8(_ object: AnyObject, _ selectorName: String) -> UInt8? {
        let sel = NSSelectorFromString(selectorName)
        guard object.responds(to: sel) else { return nil }
        guard let imp = class_getMethodImplementation(object_getClass(object), sel) else {
            return nil
        }
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt8
        return unsafeBitCast(imp, to: Fn.self)(object, sel)
    }
}
