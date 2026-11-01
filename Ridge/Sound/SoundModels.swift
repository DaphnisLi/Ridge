import AppKit
import CoreAudio
import Foundation

struct SoundOutputDevice: Identifiable, Hashable {
    /// 稳定键：设备 UID，多数据源时带 `#ds:<code>` 后缀。
    var id: String { uid }
    let objectID: AudioObjectID
    let uid: String
    let name: String
    /// CoreAudio transport fourCC，用于图标与诊断。
    let transport: UInt32
    /// 蓝牙设备电量 0…100；非蓝牙或未知为 nil。
    var batteryPercent: Int?
    var isDefault: Bool

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

struct SoundAppRow: Identifiable, Hashable {
    /// 稳定键：bundle id，否则 `pid:<n>`。
    var id: String { key }
    let key: String
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let processObjectIDs: [AudioObjectID]
    let pids: [pid_t]
    var isPlaying: Bool
    /// 0…1，持久化偏好；未接管时也显示。
    var volume: Double
    var isMuted: Bool
    /// 是否已通过 Process Tap 接管（否则滑块只改偏好，等引擎就绪再生效）。
    var isControlled: Bool
}

enum SoundTapAvailability {
    case available
    case needsMacOS142
    case needsScreenCapture
}
