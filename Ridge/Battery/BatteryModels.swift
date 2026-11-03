import Foundation

enum BatteryDeviceKind: String, Equatable, Hashable, Codable {
    case keyboard
    case mouse
    case trackpad
    case headphones
    case headset
    case gamepad
    case other

    var systemSymbol: String {
        switch self {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "touchpad.and.arrow.down"
        case .headphones: return "headphones"
        case .headset: return "headset"
        case .gamepad: return "gamecontroller"
        case .other: return "battery.100"
        }
    }
}

/// AirPods 等设备的聆听模式（IOBluetooth `listeningMode`）。
enum BatteryListeningMode: String, Equatable, Hashable {
    case off
    case noiseCancellation
    case transparency
    case adaptive

    var systemSymbol: String {
        switch self {
        case .off: return "ear"
        case .noiseCancellation: return "ear.badge.waveform"
        case .transparency: return "ear"
        case .adaptive: return "hearingdevice.and.signal.meter"
        }
    }
}

/// 岛上 / 设置展示的一条外设电量。
struct BatteryDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var kind: BatteryDeviceKind
    /// 无系统电量报告时为 nil（如部分 Sony 耳机），仍展示「已连接」。
    var percent: Int?
    var isCharging: Bool
    var isLow: Bool
    var leftPercent: Int?
    var rightPercent: Int?
    var casePercent: Int?
    /// AirPods Pro 等可读时非 nil。
    var listeningMode: BatteryListeningMode?
    var subtitle: String

    var hasBatteryReading: Bool { percent != nil }

    /// 左右耳分电量可读时才走三格；无读数的头戴耳机（如部分 Sony）走单条「电量不可用」。
    var showsSplitBuds: Bool {
        leftPercent != nil || rightPercent != nil || casePercent != nil
    }
}

/// 外设低电 / 满电岛内瞬时通知载荷。
struct BatteryPeripheralNotice: Hashable, Identifiable {
    let id: String
    let deviceID: String
    let deviceName: String
    let kind: BatteryDeviceKind
    let percent: Int
    /// 低电：触发阈值；满电：100。
    let threshold: Int
    let detail: String
}
