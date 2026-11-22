import Foundation

/// 本机电池瞬时 tip 载荷（与外设 `BatteryPeripheralNotice` 分通道）。
struct MacBatteryNotice: Identifiable, Hashable {
    /// 插电 / 满电 / 低电 / 拔电。
    enum Kind: String, Hashable, CaseIterable {
        case charging
        case full
        case low
        case unplugged
    }

    let id: String
    let kind: Kind
    let percent: Int
    let threshold: Int
    let detail: String
}
