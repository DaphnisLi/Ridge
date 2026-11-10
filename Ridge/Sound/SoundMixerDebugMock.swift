import AppKit
import CoreAudio
import Foundation

/// 混音台布局调试用假数据。验收完把 `enabled` 改回 `false`。
enum SoundMixerDebugMock {
    static let enabled = false

    static var devices: [SoundOutputDevice] {[
        SoundOutputDevice(
            objectID: 1,
            uid: "mock.speakers",
            name: L10n.Sound.previewDeviceSpeakers,
            transport: kAudioDeviceTransportTypeBuiltIn,
            batteryPercent: nil,
            isDefault: true
        ),
        SoundOutputDevice(
            objectID: 2,
            uid: "mock.airpods",
            name: L10n.Sound.previewDeviceAirPods,
            transport: kAudioDeviceTransportTypeBluetooth,
            batteryPercent: 78,
            isDefault: false
        ),
        SoundOutputDevice(
            objectID: 3,
            uid: "mock.display",
            name: "Studio Display",
            transport: kAudioDeviceTransportTypeDisplayPort,
            batteryPercent: nil,
            isDefault: false
        ),
        SoundOutputDevice(
            objectID: 4,
            uid: "mock.usb",
            name: "USB Audio DAC",
            transport: kAudioDeviceTransportTypeUSB,
            batteryPercent: nil,
            isDefault: false
        ),
        SoundOutputDevice(
            objectID: 5,
            uid: "mock.homepod",
            name: "HomePod mini",
            transport: kAudioDeviceTransportTypeAirPlay,
            batteryPercent: nil,
            isDefault: false
        )
    ]}

    static var apps: [SoundAppRow] {[
        mockApp(key: "mock.music", name: L10n.Sound.previewAppMusic, volume: 0.72, playing: true),
        mockApp(key: "mock.safari", name: L10n.Sound.previewAppSafari, volume: 0.40, playing: false),
        mockApp(key: "mock.zoom", name: "Zoom", volume: 0.88, playing: true),
        mockApp(key: "mock.chrome", name: "Chrome", volume: 0.55, playing: false),
        mockApp(key: "mock.spotify", name: "Spotify", volume: 0.63, playing: true, muted: false),
        mockApp(key: "mock.qqmusic", name: "QQ音乐", volume: 0.0, playing: false, muted: true),
        mockApp(key: "mock.cursor", name: "Cursor", volume: 0.35, playing: false)
    ]}

    private static func mockApp(
        key: String,
        name: String,
        volume: Double,
        playing: Bool,
        muted: Bool = false
    ) -> SoundAppRow {
        SoundAppRow(
            key: key,
            bundleID: key,
            name: name,
            icon: nil,
            processObjectIDs: [],
            pids: [],
            isPlaying: playing,
            volume: volume,
            isMuted: muted,
            isControlled: false
        )
    }
}
