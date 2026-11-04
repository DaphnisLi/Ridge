import AudioToolbox
import CoreAudio
import Foundation

/// 输出设备枚举与系统主输出音量。
/// 内建声卡的「扬声器 / 耳机」是同一 Device 的不同 DataSource，会展开成多条可选输出。
enum SoundDeviceService {
    private static let dataSourceUIDMarker = "#ds:"

    /// 用户可选的输出：排除虚拟设备、隐藏设备、Ridge 私有聚合等。
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

            let isDefaultDevice = (defaultID.map { $0 == id } ?? false)
            if let reason = rejectOutputReason(id: id, uid: uid, transport: transport), !isDefaultDevice {
                dropped.append((name, uid, reason))
                continue
            }
            if isDefaultDevice, let reason = rejectOutputReason(id: id, uid: uid, transport: transport) {
                AppLog.warn("Sound", "默认输出本应过滤，仍强制保留", [
                    "name": name,
                    "uid": uid,
                    "reason": reason
                ])
            }

            let sources = outputDataSources(id)
            let currentSource = currentOutputDataSource(id)
            let jackConnected = outputJackIsConnected(id)

            if !sources.isEmpty {
                // 内建声卡常见：扬声器 + 耳机 两条 DataSource；未插孔时「耳机」仍会出现在
                // DataSources 列表里，若不加过滤会像「已连接」一样一直显示在混音台。
                var visibleSources: [UInt32] = []
                for source in sources {
                    let sourceName = dataSourceName(device: id, sourceID: source) ?? name
                    if shouldOmitHeadphoneDataSource(
                        name: sourceName,
                        sourceID: source,
                        currentSource: currentSource,
                        jackConnected: jackConnected
                    ) {
                        AppLog.debug("Sound", "跳过未连接的耳机数据源", [
                            "name": sourceName,
                            "uid": uid,
                            "source": source,
                            "jack": jackConnected.map { $0 ? "in" : "out" } ?? "n/a"
                        ])
                        continue
                    }
                    visibleSources.append(source)
                }

                for source in visibleSources {
                    let sourceName = dataSourceName(device: id, sourceID: source) ?? name
                    let endpointUID = visibleSources.count == 1
                        ? uid
                        : "\(uid)\(dataSourceUIDMarker)\(source)"
                    let isDefault = isDefaultDevice && (currentSource == nil || currentSource == source)
                    kept.append(
                        SoundOutputDevice(
                            objectID: id,
                            uid: endpointUID,
                            name: sourceName,
                            transport: transport,
                            batteryPercent: batteryPercent(uid: uid, transport: transport),
                            isDefault: isDefault
                        )
                    )
                }
            } else {
                kept.append(
                    SoundOutputDevice(
                        objectID: id,
                        uid: uid,
                        name: name,
                        transport: transport,
                        batteryPercent: batteryPercent(uid: uid, transport: transport),
                        isDefault: isDefaultDevice
                    )
                )
            }
        }

        kept.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        AppLog.debug("Sound", "输出设备枚举", [
            "raw": raw.count,
            "kept": kept.count,
            "default": kept.first(where: \.isDefault)?.name ?? "none",
            "names": kept.map(\.name).joined(separator: " | ")
        ])
        for device in kept {
            AppLog.debug("Sound", "保留输出设备", [
                "name": device.name,
                "uid": device.uid,
                "default": device.isDefault,
                "transport": transportLabel(transportType(device.objectID))
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
        let deviceUID: String
        let sourceID: UInt32?
        if let range = uid.range(of: dataSourceUIDMarker) {
            deviceUID = String(uid[..<range.lowerBound])
            sourceID = UInt32(uid[range.upperBound...])
        } else {
            deviceUID = uid
            sourceID = nil
        }

        guard let id = deviceIDs().first(where: {
            CoreAudioProperty.getCFString(object: $0, kAudioDevicePropertyDeviceUID) == deviceUID
        }) else {
            AppLog.warn("Sound", "切换输出失败：找不到设备", ["uid": uid])
            return false
        }

        let setDevice = CoreAudioProperty.set(
            object: .system,
            kAudioHardwarePropertyDefaultOutputDevice,
            value: id
        )
        var setSource = true
        if let sourceID {
            setSource = CoreAudioProperty.set(
                object: id,
                kAudioDevicePropertyDataSource,
                scope: kAudioObjectPropertyScopeOutput,
                value: sourceID
            )
            if !setSource {
                AppLog.warn("Sound", "切换数据源失败", [
                    "uid": deviceUID,
                    "source": sourceID
                ])
            }
        }
        let ok = setDevice && setSource
        AppLog.info("Sound", "切换默认输出", [
            "uid": uid,
            "deviceOK": setDevice,
            "sourceOK": setSource,
            "ok": ok
        ])
        return ok
    }

    static func masterOutputVolume() -> Double {
        guard let id = defaultOutputDeviceID() else { return 0 }
        // 键盘音量键通常改 VirtualMainVolume，优先读它。
        if let virtual: Float32 = CoreAudioProperty.get(
            object: id,
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioObjectPropertyScopeOutput
        ) {
            return Double(virtual)
        }
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
        // 与键盘路径一致：优先写 VirtualMainVolume，再回退通道 VolumeScalar。
        var ok = CoreAudioProperty.set(
            object: id,
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioObjectPropertyScopeOutput,
            value: scalar
        )
        ok = CoreAudioProperty.set(
            object: id,
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            value: scalar
        ) || ok
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
        // 仅对聚合设备看 canBeDefault，避免误杀蓝牙耳机等实体设备。
        if transport == kAudioDeviceTransportTypeAggregate, !canBeDefaultOutput(id) {
            return "cannotBeDefault"
        }
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
        return true
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        CoreAudioProperty.get(object: id, kAudioDevicePropertyTransportType) ?? 0
    }

    private static func batteryPercent(uid: String, transport: UInt32) -> Int? {
        guard transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
        else {
            return nil
        }
        // 多数据源 UID 带 `#ds:`，电量仍按设备本体地址查。
        let deviceUID = uid.components(separatedBy: dataSourceUIDMarker).first ?? uid
        let percent = SoundBluetoothBattery.percent(forAudioDeviceUID: deviceUID)
        if let percent {
            AppLog.debug("Sound", "蓝牙电量", ["uid": deviceUID, "percent": percent])
        }
        return percent
    }

    private static func transportLabel(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return "builtIn"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypePCI: return "pci"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeFireWire: return "firewire"
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth" // 'blue'
        case kAudioDeviceTransportTypeBluetoothLE: return "bluetoothLE" // 'blea'
        case kAudioDeviceTransportTypeHDMI: return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort: return "displayPort"
        case kAudioDeviceTransportTypeAirPlay: return "airPlay"
        case kAudioDeviceTransportTypeAVB: return "avb"
        case kAudioDeviceTransportTypeThunderbolt: return "thunderbolt"
        default: return String(format: "0x%08x", type)
        }
    }

    // MARK: - Data sources（扬声器 / 耳机）

    private static func outputDataSources(_ id: AudioObjectID) -> [UInt32] {
        CoreAudioProperty.getArray(
            object: id,
            kAudioDevicePropertyDataSources,
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    private static func currentOutputDataSource(_ id: AudioObjectID) -> UInt32? {
        CoreAudioProperty.get(
            object: id,
            kAudioDevicePropertyDataSource,
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    /// `nil` = 设备不支持插孔状态（仍按名称过滤未选中的耳机源）。
    private static func outputJackIsConnected(_ id: AudioObjectID) -> Bool? {
        guard let value: UInt32 = CoreAudioProperty.get(
            object: id,
            kAudioDevicePropertyJackIsConnected,
            scope: kAudioObjectPropertyScopeOutput
        ) else {
            return nil
        }
        return value != 0
    }

    private static func isHeadphoneDataSourceName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("headphone") || name.contains("耳机")
    }

    /// 未插线时 HAL 仍可能枚举「耳机」DataSource；混音台只保留真正可用或当前选中的。
    private static func shouldOmitHeadphoneDataSource(
        name: String,
        sourceID: UInt32,
        currentSource: UInt32?,
        jackConnected: Bool?
    ) -> Bool {
        guard isHeadphoneDataSourceName(name) else { return false }
        if currentSource == sourceID { return false }
        if let jackConnected {
            return !jackConnected
        }
        return true
    }

    private static func dataSourceName(device: AudioObjectID, sourceID: UInt32) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var source = sourceID
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(
                device,
                &address,
                UInt32(MemoryLayout<UInt32>.size),
                &source,
                &dataSize,
                ptr
            )
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    // MARK: - Private

    private static func deviceIDs() -> [AudioObjectID] {
        CoreAudioProperty.getArray(object: .system, kAudioHardwarePropertyDevices)
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        if channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0 {
            return true
        }
        let streams: [AudioObjectID] = CoreAudioProperty.getArray(
            object: id,
            kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeOutput
        )
        return streams.count > 0
    }

    /// 用 StreamConfiguration 数声道，比单纯数 stream 对象更稳（部分蓝牙耳机适用）。
    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, raw) == noErr else {
            return 0
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var total = 0
        for buffer in buffers {
            total += Int(buffer.mNumberChannels)
        }
        return total
    }
}
