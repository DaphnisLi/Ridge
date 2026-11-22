import Combine
import Foundation

/// 本机电池 tip 偏好：与外设 `BatterySettings` **分通道**；四态随小组件总开关，仅低电阈值可配。
@MainActor
final class MacBatterySettings: ObservableObject {
    static let shared = MacBatterySettings()

    private enum Key {
        static let lowThreshold = "macBattery.lowThreshold.v1"
    }

    /// 设置页四档：10 / 15（推荐）/ 20 / 25；默认与外设一致为 15。
    static let lowThresholdPresets: [Int] = [10, 15, 20, 25]
    static let defaultLowThresholdPercent: Int = 15

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

    static func snapToLowThresholdPreset(_ value: Int) -> Int {
        guard let nearest = lowThresholdPresets.min(by: { abs($0 - value) < abs($1 - value) }) else {
            return defaultLowThresholdPercent
        }
        return nearest
    }

    private init() {
        let defaults = UserDefaults.standard
        let raw = defaults.object(forKey: Key.lowThreshold) as? Int ?? Self.defaultLowThresholdPercent
        lowThresholdPercent = Self.snapToLowThresholdPreset(raw)
        if raw != lowThresholdPercent {
            UserDefaults.standard.set(lowThresholdPercent, forKey: Key.lowThreshold)
        }
    }

    func restoreDefaults() {
        lowThresholdPercent = Self.defaultLowThresholdPercent
        AppLog.info("MacBattery", "本机电池提示已恢复默认")
    }
}
