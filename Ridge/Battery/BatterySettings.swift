import Combine
import Foundation

/// 电量模块：低电 / 满电告警偏好与按设备稍后提醒。
@MainActor
final class BatterySettings: ObservableObject {
    static let shared = BatterySettings()

    private enum Key {
        static let lowEnabled = "battery.lowAlertEnabled.v1"
        static let lowThreshold = "battery.lowThreshold.v1"
        static let fullEnabled = "battery.fullAlertEnabled.v1"
        static let snoozeMap = "battery.lowSnoozeUntil.v1"
    }

    @Published var lowAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lowAlertEnabled, forKey: Key.lowEnabled)
            AppLog.info("Battery", "低电告警开关", ["enabled": lowAlertEnabled])
        }
    }

    /// 低电触发阈值 5…40，默认 15。
    @Published var lowThresholdPercent: Int {
        didSet {
            let clamped = min(40, max(5, lowThresholdPercent))
            if clamped != lowThresholdPercent {
                lowThresholdPercent = clamped
                return
            }
            UserDefaults.standard.set(lowThresholdPercent, forKey: Key.lowThreshold)
            AppLog.info("Battery", "低电阈值", ["percent": lowThresholdPercent])
        }
    }

    @Published var fullChargeAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(fullChargeAlertEnabled, forKey: Key.fullEnabled)
            AppLog.info("Battery", "满电告警开关", ["enabled": fullChargeAlertEnabled])
        }
    }

    /// deviceID → 低电免打扰截止。
    private var snoozeUntilByDevice: [String: TimeInterval] {
        didSet {
            UserDefaults.standard.set(snoozeUntilByDevice, forKey: Key.snoozeMap)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        lowAlertEnabled = defaults.object(forKey: Key.lowEnabled) as? Bool ?? true
        let raw = defaults.object(forKey: Key.lowThreshold) as? Int ?? 15
        lowThresholdPercent = min(40, max(5, raw))
        fullChargeAlertEnabled = defaults.object(forKey: Key.fullEnabled) as? Bool ?? true
        snoozeUntilByDevice = defaults.dictionary(forKey: Key.snoozeMap) as? [String: TimeInterval] ?? [:]
    }

    func isLowSnoozed(deviceID: String, now: Date = Date()) -> Bool {
        guard let ts = snoozeUntilByDevice[deviceID] else { return false }
        return Date(timeIntervalSince1970: ts) > now
    }

    func snoozeLowAlert(deviceID: String, minutes: Int = 30) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        snoozeUntilByDevice[deviceID] = until.timeIntervalSince1970
        AppLog.info("Battery", "低电稍后提醒", [
            "device": deviceID.prefix(12).description,
            "minutes": minutes
        ])
    }

    func clearSnooze(deviceID: String) {
        snoozeUntilByDevice.removeValue(forKey: deviceID)
    }
}
