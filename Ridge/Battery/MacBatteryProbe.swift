import Foundation
import IOKit.ps

/// 本机内置电池快照（笔记本）；台式无内置电池时 `snapshot()` 为 nil。
enum MacBatteryProbe {
    struct Snapshot: Equatable {
        var percent: Int
        /// IOPS「正在充电」；优化充电暂停时可能为 false。
        var isCharging: Bool
        var isCharged: Bool
        /// 电源线已接上（AC），含「已接电但未在充」。
        var isOnAC: Bool
        /// AC / Battery 等，仅日志用。
        var powerState: String
    }

    /// 是否存在可读的内置电池（台式通常 false）。
    static var hasInternalBattery: Bool {
        snapshot() != nil
    }

    static func snapshot() -> Snapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty
        else {
            return nil
        }

        for source in list {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any]
            else { continue }

            let type = raw[kIOPSTypeKey] as? String
            // 只要内置电池；外接 UPS 等跳过。
            guard type == kIOPSInternalBatteryType else { continue }

            let current = raw[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = raw[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent: Int
            if maxCapacity > 0 {
                percent = Swift.min(Swift.max(Int((Double(current) / Double(maxCapacity) * 100).rounded()), 0), 100)
            } else {
                percent = Swift.min(Swift.max(current, 0), 100)
            }
            let isCharging = (raw[kIOPSIsChargingKey] as? Bool) ?? false
            let isCharged = (raw[kIOPSIsChargedKey] as? Bool) ?? (percent >= 100 && isCharging)
            let powerState = (raw[kIOPSPowerSourceStateKey] as? String) ?? ""
            let isOnAC = powerState == kIOPSACPowerValue
                || isCharging
                || isCharged
            return Snapshot(
                percent: percent,
                isCharging: isCharging,
                isCharged: isCharged,
                isOnAC: isOnAC,
                powerState: powerState
            )
        }
        return nil
    }
}
