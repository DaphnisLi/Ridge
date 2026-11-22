import Combine
import Foundation

/// 本机电池 tip 偏好：与外设 `BatterySettings` **分通道**，键前缀独立。
@MainActor
final class MacBatterySettings: ObservableObject {
    static let shared = MacBatterySettings()

    private enum Key {
        static let chargingEnabled = "macBattery.chargingAlertEnabled.v1"
        static let lowEnabled = "macBattery.lowAlertEnabled.v1"
        static let lowThreshold = "macBattery.lowThreshold.v1"
        static let fullEnabled = "macBattery.fullAlertEnabled.v1"
        static let unplugEnabled = "macBattery.unplugAlertEnabled.v1"
    }

    static let lowThresholdPresets: [Int] = [10, 15, 20, 25]
    static let defaultLowThresholdPercent: Int = 20

    /// 插入电源时提示。
    @Published var chargingAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(chargingAlertEnabled, forKey: Key.chargingEnabled)
            AppLog.info("MacBattery", "插电提示开关", ["enabled": chargingAlertEnabled])
        }
    }

    @Published var lowAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lowAlertEnabled, forKey: Key.lowEnabled)
            AppLog.info("MacBattery", "低电提示开关", ["enabled": lowAlertEnabled])
        }
    }

    @Published var lowThresholdPercent: Int {
        didSet {
            let snapped = Self.snapToLowThresholdPreset(lowThresholdPercent)
            if snapped != lowThresholdPercent {
                lowThresholdPercent = snapped
                return
            }
            UserDefaults.standard.set(lowThresholdPercent, forKey: Key.lowThreshold)
            AppLog.info("MacBattery", "低电阈值", ["percent": lowThresholdPercent])
        }
    }

    @Published var fullChargeAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(fullChargeAlertEnabled, forKey: Key.fullEnabled)
            AppLog.info("MacBattery", "充满提示开关", ["enabled": fullChargeAlertEnabled])
        }
    }

    /// 拔掉电源时提示。
    @Published var unplugAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(unplugAlertEnabled, forKey: Key.unplugEnabled)
            AppLog.info("MacBattery", "拔电提示开关", ["enabled": unplugAlertEnabled])
        }
    }

    static func snapToLowThresholdPreset(_ value: Int) -> Int {
        guard let nearest = lowThresholdPresets.min(by: { abs($0 - value) < abs($1 - value) }) else {
            return defaultLowThresholdPercent
        }
        return nearest
    }

    private init() {
        let defaults = UserDefaults.standard
        chargingAlertEnabled = defaults.object(forKey: Key.chargingEnabled) as? Bool ?? true
        lowAlertEnabled = defaults.object(forKey: Key.lowEnabled) as? Bool ?? true
        let raw = defaults.object(forKey: Key.lowThreshold) as? Int ?? Self.defaultLowThresholdPercent
        lowThresholdPercent = Self.snapToLowThresholdPreset(raw)
        fullChargeAlertEnabled = defaults.object(forKey: Key.fullEnabled) as? Bool ?? true
        unplugAlertEnabled = defaults.object(forKey: Key.unplugEnabled) as? Bool ?? true
        if raw != lowThresholdPercent {
            UserDefaults.standard.set(lowThresholdPercent, forKey: Key.lowThreshold)
        }
    }

    func restoreDefaults() {
        chargingAlertEnabled = true
        lowAlertEnabled = true
        lowThresholdPercent = Self.defaultLowThresholdPercent
        fullChargeAlertEnabled = true
        unplugAlertEnabled = true
        AppLog.info("MacBattery", "本机电池提示已恢复默认")
    }
}
