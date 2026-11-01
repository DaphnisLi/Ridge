import CoreAudio
import Foundation

/// 输出设备枚举与系统主输出音量。
enum SoundDeviceService {
    /// 用户可选的输出设备：排除虚拟设备、隐藏设备、Ridge 私有聚合等。
    static func outputDevices() -> [SoundOutputDevice] {
        let defaultID = defaultOutputDeviceID()
        let raw = deviceIDs()
        var kept: [SoundOutputDevice] = []
        var dropped: [(name: String, uid: String, reason: String)] = []

        for id in raw {
            let name = CoreAudioProperty.getCFString(object: id, kAudioDevicePropertyDeviceNameCFString) ?? "?"
            let uid = CoreAudioProperty.getCFString(object: id, kAudioDevicePropertyDeviceUID) ?? "?"
            let transport = transportType(id)
            guard hasOutput(id) else { continue }

            let isDefault = (defaultID.map { $0 == id } ?? false)
            // 系统当前默认输出必须保留，否则列表空/无默认，按钮切换与 App 路由都会坏。
            if let reason = rejectOutputReason(id: id, uid: uid, transport: transport), !isDefault {
                dropped.append((name, uid, reason))
                continue
            }
            if isDefault, let reason = rejectOutputReason(id: id, uid: uid, transport: transport) {
                AppLog.warn("Sound", "默认输出本应过滤，仍强制保留", [
                    "name": name,
                    "uid": uid,
                    "reason": reason
                ])
            }

            kept.append(
                SoundOutputDevice(id: id, uid: uid, name: name, isDefault: isDefault)
            )
        }

        kept.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        AppLog.info("Sound", "输出设备枚举", [
            "raw": raw.count,
            "kept": kept.count,
            "default": kept.first(where: \.isDefault)?.name ?? "none"
        ])
        for device in kept {
            AppLog.debug("Sound", "保留输出设备", [
                "name": device.name,
                "uid": device.uid,
                "default": device.isDefault,
                "transport": transportLabel(transportType(device.id))
            ])
        }
        for item in dropped {
            AppLog.debug("Sound", "过滤输出设备", [
                "name": item.name,
                "uid": item.uid,
                "reason": item.reason
            ])
        }
        return kept
    }

    static func defaultOutputDeviceID() -> AudioObjectID? {
        CoreAudioProperty.get(object: .system, kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func setDefaultOutput(uid: String) -> Bool {
        guard let id = deviceIDs().first(where: {
            CoreAudioProperty.getCFString(object: $0, kAudioDevicePropertyDeviceUID) == uid
        }) else { return false }
        let ok = CoreAudioProperty.set(
            object: .system,
            kAudioHardwarePropertyDefaultOutputDevice,
            value: id
        )
        AppLog.info("Sound", "切换默认输出", ["uid": uid, "ok": ok])
        return ok
    }

    static func masterOutputVolume() -> Double {
        guard let id = defaultOutputDeviceID() else { return 0 }
        if let scalar: Float32 = CoreAudioProperty.get(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput
        ) {
            return Double(scalar)
        }
        if let left: Float32 = CoreAudioProperty.get(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 1
        ),
           let right: Float32 = CoreAudioProperty.get(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 2
        ) {
            return Double((left + right) / 2)
        }
        return 0
    }

    @discardableResult
    static func setMasterOutputVolume(_ value: Double) -> Bool {
        guard let id = defaultOutputDeviceID() else { return false }
        let scalar = Float32(min(1, max(0, value)))
        var ok = CoreAudioProperty.set(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            value: scalar
        )
        ok = CoreAudioProperty.set(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 1,
            value: scalar
        ) || ok
        ok = CoreAudioProperty.set(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 2,
            value: scalar
        ) || ok
        return ok
    }

    // MARK: - Filter

    private static func rejectOutputReason(
        id: AudioObjectID,
        uid: String,
        transport: UInt32
    ) -> String? {
        if isHidden(id) { return "hidden" }
        if uid.hasPrefix("app.daphnis.Ridge.sound.agg.") { return "ridgeAggregate" }
        if uid.lowercased().contains("soundrouter") { return "thirdPartyAggregate" }
        // 虚拟声卡（Zoom / Teams / BlackHole 等）不进列表。
        if transport == kAudioDeviceTransportTypeVirtual { return "virtual" }
        // 不能作为系统默认输出的设备（含多数私有聚合）。
        if !canBeDefaultOutput(id) { return "cannotBeDefault" }
        return nil
    }

    private static func isHidden(_ id: AudioObjectID) -> Bool {
        if let hidden: UInt32 = CoreAudioProperty.get(object: id, kAudioDevicePropertyIsHidden) {
            return hidden != 0
        }
        return false
    }

    private static func canBeDefaultOutput(_ id: AudioObjectID) -> Bool {
        if let flag: UInt32 = CoreAudioProperty.get(
            object: id,
            kAudioDevicePropertyDeviceCanBeDefaultDevice,
            scope: kAudioObjectPropertyScopeOutput
        ) {
            return flag != 0
        }
        // 读失败时保守保留，避免误杀内置扬声器。
        return true
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        CoreAudioProperty.get(object: id, kAudioDevicePropertyTransportType) ?? 0
    }

    private static func transportLabel(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return "builtIn"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypePCI: return "pci"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeFireWire: return "firewire"
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "bluetoothLE"
        case kAudioDeviceTransportTypeHDMI: return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort: return "displayPort"
        case kAudioDeviceTransportTypeAirPlay: return "airPlay"
        case kAudioDeviceTransportTypeAVB: return "avb"
        case kAudioDeviceTransportTypeThunderbolt: return "thunderbolt"
        default: return String(format: "0x%08x", type)
        }
    }

    // MARK: - Private

    private static func deviceIDs() -> [AudioObjectID] {
        CoreAudioProperty.getArray(object: .system, kAudioHardwarePropertyDevices)
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        let streams: [AudioObjectID] = CoreAudioProperty.getArray(
            object: id,
            kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeOutput
        )
        return streams.count > 0
    }
}
