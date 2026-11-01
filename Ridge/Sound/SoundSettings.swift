import Combine
import Foundation

/// 声音模块持久化：每 App 输出音量偏好。
@MainActor
final class SoundSettings: ObservableObject {
    static let shared = SoundSettings()

    private enum Key {
        static let appVolumes = "sound.appVolumes.v1"
        static let appMuted = "sound.appMuted.v1"
        static let rememberVolumes = "sound.rememberVolumes.v1"
    }

    /// bundleID → 0…1
    @Published private(set) var appVolumes: [String: Double]
    @Published private(set) var appMuted: [String: Bool]
    @Published var rememberVolumes: Bool {
        didSet { UserDefaults.standard.set(rememberVolumes, forKey: Key.rememberVolumes) }
    }

    private init() {
        let defaults = UserDefaults.standard
        appVolumes = (defaults.dictionary(forKey: Key.appVolumes) as? [String: Double]) ?? [:]
        appMuted = (defaults.dictionary(forKey: Key.appMuted) as? [String: Bool]) ?? [:]
        rememberVolumes = defaults.object(forKey: Key.rememberVolumes) as? Bool ?? true
        AppLog.debug("Sound", "已加载声音设置", [
            "volumes": appVolumes.count,
            "muted": appMuted.count
        ])
    }

    func volume(for key: String) -> Double {
        appVolumes[key] ?? 1
    }

    func isMuted(for key: String) -> Bool {
        appMuted[key] ?? false
    }

    func setVolume(_ value: Double, for key: String) {
        let clamped = min(1, max(0, value))
        var next = appVolumes
        if abs(clamped - 1) < 0.001 {
            next.removeValue(forKey: key)
        } else {
            next[key] = clamped
        }
        appVolumes = next
        if rememberVolumes {
            UserDefaults.standard.set(next, forKey: Key.appVolumes)
        }
        AppLog.info("Sound", "写入 App 音量偏好", ["key": key, "volume": clamped])
    }

    func setMuted(_ muted: Bool, for key: String) {
        var next = appMuted
        if muted {
            next[key] = true
        } else {
            next.removeValue(forKey: key)
        }
        appMuted = next
        if rememberVolumes {
            UserDefaults.standard.set(next, forKey: Key.appMuted)
        }
    }

    func resetAllAppVolumes() {
        appVolumes = [:]
        appMuted = [:]
        UserDefaults.standard.removeObject(forKey: Key.appVolumes)
        UserDefaults.standard.removeObject(forKey: Key.appMuted)
        AppLog.info("Sound", "已重置全部 App 音量偏好")
    }
}
