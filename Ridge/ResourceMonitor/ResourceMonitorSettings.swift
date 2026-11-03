import Combine
import Foundation

/// 资源监控用户偏好。
@MainActor
final class ResourceMonitorSettings: ObservableObject {
    static let shared = ResourceMonitorSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let alertEnabled = "resourceMonitor.alertEnabled"
        static let ramThreshold = "resourceMonitor.ramThresholdPercent"
        static let singleAppGB = "resourceMonitor.singleAppAlertGB"
        static let muteUntil = "resourceMonitor.muteUntil"
    }

    /// 自动化告警：RAM 过载时走岛内瞬时通知。
    @Published var alertEnabled: Bool {
        didSet {
            defaults.set(alertEnabled, forKey: Key.alertEnabled)
            AppLog.info("ResourceMonitor", "告警开关", ["enabled": alertEnabled])
        }
    }

    /// RAM 占用阈值（百分比，默认 95）。
    @Published var ramThresholdPercent: Double {
        didSet {
            defaults.set(ramThresholdPercent, forKey: Key.ramThreshold)
            AppLog.info("ResourceMonitor", "RAM 阈值", ["percent": ramThresholdPercent])
        }
    }

    /// 单 App 告警辅助阈值（GB，默认 8；仅文案/规则展示，触发仍以整机阈值为准）。
    @Published var singleAppAlertGB: Double {
        didSet {
            defaults.set(singleAppAlertGB, forKey: Key.singleAppGB)
        }
    }

    /// 告警静音截止时间。
    @Published private(set) var muteUntil: Date? {
        didSet {
            if let muteUntil {
                defaults.set(muteUntil.timeIntervalSince1970, forKey: Key.muteUntil)
            } else {
                defaults.removeObject(forKey: Key.muteUntil)
            }
        }
    }

    var isMuted: Bool {
        guard let muteUntil else { return false }
        return muteUntil > Date()
    }

    private init() {
        // 默认关闭自动化告警；首次安装阈值为 95%。
        alertEnabled = defaults.object(forKey: Key.alertEnabled) as? Bool ?? false
        let threshold = defaults.object(forKey: Key.ramThreshold) as? Double ?? 95
        ramThresholdPercent = min(99, max(50, threshold))
        singleAppAlertGB = defaults.object(forKey: Key.singleAppGB) as? Double ?? 8
        if let ts = defaults.object(forKey: Key.muteUntil) as? Double, ts > 0 {
            muteUntil = Date(timeIntervalSince1970: ts)
        } else {
            muteUntil = nil
        }
    }

    func muteAlerts(minutes: Int) {
        muteUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        AppLog.info("ResourceMonitor", "告警已静音", ["minutes": minutes])
    }

    func clearMute() {
        muteUntil = nil
        AppLog.info("ResourceMonitor", "告警静音已清除")
    }
}
