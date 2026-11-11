import Combine
import Foundation

/// 多外设同时在线时的岛上排布策略。
enum BatteryPeripheralSortMode: String, CaseIterable, Identifiable {
    case recentActivity
    case batteryLowToHigh
    case connectionOrder

    var id: String { rawValue }
}

/// 点击岛上外设卡片时的行为。
enum BatteryPeripheralClickAction: String, CaseIterable, Identifiable {
    case openBluetoothSettings
    case refreshBatteryOnly

    var id: String { rawValue }
}

/// 电量模块：低电 / 满电 / 接入告警偏好与按设备稍后提醒。
/// 总开关在小组件库 `builtin.peripheralTip`；本类只存各档细节。
@MainActor
final class BatterySettings: ObservableObject {
    static let shared = BatterySettings()

    private enum Key {
        static let lowEnabled = "battery.lowAlertEnabled.v1"
        static let lowThreshold = "battery.lowThreshold.v1"
        static let fullEnabled = "battery.fullAlertEnabled.v1"
        static let connectEnabled = "battery.connectAlertEnabled.v1"
        static let snoozeMap = "battery.lowSnoozeUntil.v1"
        static let sortMode = "battery.peripheralSortMode.v1"
        static let clickAction = "battery.peripheralClickAction.v1"
    }

    /// 设置页四档：10 / 15（推荐）/ 20 / 25。
    static let lowThresholdPresets: [Int] = [10, 15, 20, 25]
    static let defaultLowThresholdPercent: Int = 15

    @Published var lowAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lowAlertEnabled, forKey: Key.lowEnabled)
            AppLog.info("Battery", "低电告警开关", ["enabled": lowAlertEnabled])
        }
    }

    /// 低电触发阈值；仅允许预设档，默认 15。
    @Published var lowThresholdPercent: Int {
        didSet {
            let snapped = Self.snapToLowThresholdPreset(lowThresholdPercent)
            if snapped != lowThresholdPercent {
                lowThresholdPercent = snapped
                return
            }
            UserDefaults.standard.set(lowThresholdPercent, forKey: Key.lowThreshold)
            AppLog.info("Battery", "低电阈值", ["percent": lowThresholdPercent])
        }
    }

    /// 旧滑条值落档到最近预设。
    static func snapToLowThresholdPreset(_ value: Int) -> Int {
        guard let nearest = lowThresholdPresets.min(by: { abs($0 - value) < abs($1 - value) }) else {
            return defaultLowThresholdPercent
        }
        return nearest
    }

    @Published var fullChargeAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(fullChargeAlertEnabled, forKey: Key.fullEnabled)
            AppLog.info("Battery", "满电告警开关", ["enabled": fullChargeAlertEnabled])
        }
    }

    /// 外设新接入时瞬时提示；默认开启。
    @Published var connectAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(connectAlertEnabled, forKey: Key.connectEnabled)
            AppLog.info("Battery", "接入告警开关", ["enabled": connectAlertEnabled])
        }
    }

    /// 多外设排布：默认按最近使用活跃度。
    @Published var peripheralSortMode: BatteryPeripheralSortMode {
        didSet {
            UserDefaults.standard.set(peripheralSortMode.rawValue, forKey: Key.sortMode)
            AppLog.info("Battery", "外设排序策略已更新", ["mode": peripheralSortMode.rawValue])
        }
    }

    /// 点击岛上外设卡片：默认打开蓝牙设置。
    @Published var peripheralClickAction: BatteryPeripheralClickAction {
        didSet {
            UserDefaults.standard.set(peripheralClickAction.rawValue, forKey: Key.clickAction)
            AppLog.info("Battery", "外设卡片点击操作已更新", ["action": peripheralClickAction.rawValue])
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
        let raw = defaults.object(forKey: Key.lowThreshold) as? Int ?? Self.defaultLowThresholdPercent
        lowThresholdPercent = Self.snapToLowThresholdPreset(raw)
        fullChargeAlertEnabled = defaults.object(forKey: Key.fullEnabled) as? Bool ?? true
        connectAlertEnabled = defaults.object(forKey: Key.connectEnabled) as? Bool ?? true
        snoozeUntilByDevice = defaults.dictionary(forKey: Key.snoozeMap) as? [String: TimeInterval] ?? [:]
        if let rawSort = defaults.string(forKey: Key.sortMode),
           let mode = BatteryPeripheralSortMode(rawValue: rawSort) {
            peripheralSortMode = mode
        } else {
            peripheralSortMode = .recentActivity
        }
        if let rawClick = defaults.string(forKey: Key.clickAction),
           let action = BatteryPeripheralClickAction(rawValue: rawClick) {
            peripheralClickAction = action
        } else {
            peripheralClickAction = .openBluetoothSettings
        }
        if raw != lowThresholdPercent {
            UserDefaults.standard.set(lowThresholdPercent, forKey: Key.lowThreshold)
            AppLog.info("Battery", "低电阈值已对齐预设档", [
                "from": raw,
                "to": lowThresholdPercent
            ])
        }
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

    /// 外设提示配置页「恢复默认」：三档开关 + 低电阈值。
    func restoreTipDefaults() {
        lowAlertEnabled = true
        lowThresholdPercent = Self.defaultLowThresholdPercent
        fullChargeAlertEnabled = true
        connectAlertEnabled = true
        AppLog.info("Battery", "外设提示已恢复默认")
    }

    /// 电量页「恢复默认」：排序与点击操作。
    func restoreDeckDefaults() {
        peripheralSortMode = .recentActivity
        peripheralClickAction = .openBluetoothSettings
        AppLog.info("Battery", "电量页排序与点击已恢复默认")
    }
}
