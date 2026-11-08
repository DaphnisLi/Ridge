import Combine
import Foundation

/// 久坐起身提醒偏好。
@MainActor
final class MoveReminderSettings: ObservableObject {
    static let shared = MoveReminderSettings()

    private enum Key {
        static let activeMinutes = "moveReminder.activeMinutes.v1"
        static let leaveMinutes = "moveReminder.leaveMinutes.v1"
        static let restMinutes = "moveReminder.restMinutes.v2"
        static let haptic = "moveReminder.haptic.v1"
        static let smartAvoid = "moveReminder.smartAvoid.v1"
        static let muteUntil = "moveReminder.muteUntil.v1"
        static let snoozeUntil = "moveReminder.snoozeUntil.v1"
    }

    private let defaults = UserDefaults.standard

    /// 连续「在电脑前」达到该分钟数后提醒。可选 30 / 60 / 90 / 120。
    /// 变更时按档位下标映射建议活动时长（轻 / 中 / 重）。
    @Published var activeTriggerMinutes: Int {
        didSet {
            let clamped = Self.clampActive(activeTriggerMinutes)
            if clamped != activeTriggerMinutes {
                activeTriggerMinutes = clamped
                return
            }
            let previous = defaults.object(forKey: Key.activeMinutes) as? Int
            defaults.set(clamped, forKey: Key.activeMinutes)
            // 仅用户切换活跃档时联动；init 赋值不改建议活动。
            if let previous {
                let from = Self.clampActive(previous)
                if from != clamped {
                    remapSuggestedRest(fromActive: from, toActive: clamped)
                }
            }
        }
    }

    /// 闲置达到该分钟数 → 判定离开并清零。可选 3 / 5 / 10。
    @Published var leaveResetMinutes: Int {
        didSet {
            let clamped = Self.clampLeave(leaveResetMinutes)
            if clamped != leaveResetMinutes {
                leaveResetMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Key.leaveMinutes)
        }
    }

    /// 建议活动时长（用户自选）；选项随 `activeTriggerMinutes` 联动分档。
    @Published var suggestedRestMinutes: Int {
        didSet {
            let clamped = Self.clampRest(
                suggestedRestMinutes,
                forActive: activeTriggerMinutes
            )
            if clamped != suggestedRestMinutes {
                suggestedRestMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Key.restMinutes)
        }
    }

    @Published var hapticEnabled: Bool {
        didSet { defaults.set(hapticEnabled, forKey: Key.haptic) }
    }

    /// 全屏演示 / 会议中 / 麦占用时暂停累计。
    @Published var smartAvoidEnabled: Bool {
        didSet { defaults.set(smartAvoidEnabled, forKey: Key.smartAvoid) }
    }

    private init() {
        let defaults = UserDefaults.standard
        let active = Self.clampActive(
            defaults.object(forKey: Key.activeMinutes) as? Int ?? 30
        )
        let leave = Self.clampLeave(
            defaults.object(forKey: Key.leaveMinutes) as? Int ?? 5
        )
        // 旧档或与当前活跃档不匹配时，钳到当前档首项。
        let storedRest = defaults.object(forKey: Key.restMinutes) as? Int
            ?? defaults.object(forKey: "moveReminder.restMinutes.v1") as? Int
            ?? Self.restOptions(for: active)[0]
        let rest = Self.clampRest(storedRest, forActive: active)
        activeTriggerMinutes = active
        leaveResetMinutes = leave
        suggestedRestMinutes = rest
        defaults.removeObject(forKey: "moveReminder.restMinutes.v1")
        if defaults.object(forKey: Key.haptic) == nil {
            hapticEnabled = false
        } else {
            hapticEnabled = defaults.bool(forKey: Key.haptic)
        }
        if defaults.object(forKey: Key.smartAvoid) == nil {
            smartAvoidEnabled = false
        } else {
            smartAvoidEnabled = defaults.bool(forKey: Key.smartAvoid)
        }
    }

    var activeTriggerSeconds: TimeInterval { TimeInterval(activeTriggerMinutes * 60) }
    var leaveResetSeconds: TimeInterval { TimeInterval(leaveResetMinutes * 60) }

    /// 当前活跃档对应的建议活动三档（轻 / 中 / 重）。
    var restOptionsForActive: [Int] {
        Self.restOptions(for: activeTriggerMinutes)
    }

    static let activeOptions = [30, 60, 90, 120]
    static let leaveOptions = [3, 5, 10]

    /// 连续活跃 → 建议活动三档。
    /// 30→2/3/4；60→4/6/8；90→7/9/11；120→10/12/15。
    static func restOptions(for activeMinutes: Int) -> [Int] {
        switch clampActive(activeMinutes) {
        case 30: return [2, 3, 4]
        case 60: return [4, 6, 8]
        case 90: return [7, 9, 11]
        case 120: return [10, 12, 15]
        default: return [2, 3, 4]
        }
    }

    private static func clampActive(_ v: Int) -> Int {
        activeOptions.contains(v) ? v : 30
    }

    private static func clampLeave(_ v: Int) -> Int {
        leaveOptions.contains(v) ? v : 5
    }

    private static func clampRest(_ v: Int, forActive active: Int) -> Int {
        let opts = restOptions(for: active)
        return opts.contains(v) ? v : opts[0]
    }

    /// 切换活跃档时保留「轻/中/重」下标，映射到新档分钟数。
    private func remapSuggestedRest(fromActive: Int, toActive: Int) {
        let oldOpts = Self.restOptions(for: fromActive)
        let newOpts = Self.restOptions(for: toActive)
        let idx = oldOpts.firstIndex(of: suggestedRestMinutes) ?? 0
        let mapped = newOpts[min(idx, newOpts.count - 1)]
        guard mapped != suggestedRestMinutes else {
            AppLog.info("MoveReminder", "活跃档已切换，建议活动仍落在同档分钟", [
                "active": toActive,
                "rest": mapped
            ])
            return
        }
        suggestedRestMinutes = mapped
        AppLog.info("MoveReminder", "活跃档联动建议活动时长", [
            "fromActive": fromActive,
            "toActive": toActive,
            "tier": idx,
            "rest": mapped
        ])
    }

    func restoreDefaults() {
        activeTriggerMinutes = 30
        leaveResetMinutes = 5
        suggestedRestMinutes = Self.restOptions(for: 30)[0]
        hapticEnabled = false
        smartAvoidEnabled = false
        clearMute()
        clearSnooze()
        AppLog.info("MoveReminder", "已恢复默认设置", [
            "active": 30,
            "rest": suggestedRestMinutes,
            "haptic": false,
            "smartAvoid": false
        ])
    }

    // MARK: - Mute / Snooze

    func muteForRestOfDay() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let next = cal.date(byAdding: .day, value: 1, to: start) ?? Date().addingTimeInterval(86400)
        defaults.set(next.timeIntervalSince1970, forKey: Key.muteUntil)
        AppLog.info("MoveReminder", "今天不再提醒", ["until": ISO8601DateFormatter().string(from: next)])
    }

    func snooze(minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        defaults.set(until.timeIntervalSince1970, forKey: Key.snoozeUntil)
        AppLog.info("MoveReminder", "稍后提醒", ["minutes": minutes])
    }

    func clearMute() {
        defaults.removeObject(forKey: Key.muteUntil)
    }

    func clearSnooze() {
        defaults.removeObject(forKey: Key.snoozeUntil)
    }

    func isMutedNow(at date: Date = Date()) -> Bool {
        let mute = defaults.double(forKey: Key.muteUntil)
        if mute > 0, date.timeIntervalSince1970 < mute { return true }
        if mute > 0, date.timeIntervalSince1970 >= mute {
            defaults.removeObject(forKey: Key.muteUntil)
        }
        return false
    }

    func isSnoozedNow(at date: Date = Date()) -> Bool {
        let snooze = defaults.double(forKey: Key.snoozeUntil)
        if snooze > 0, date.timeIntervalSince1970 < snooze { return true }
        if snooze > 0, date.timeIntervalSince1970 >= snooze {
            defaults.removeObject(forKey: Key.snoozeUntil)
        }
        return false
    }
}
