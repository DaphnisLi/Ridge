import AppKit
import CoreAudio
import Foundation

struct SoundOutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    var isDefault: Bool
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
