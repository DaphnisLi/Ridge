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
    @Published var activeTriggerMinutes: Int {
        didSet {
            let clamped = Self.clampActive(activeTriggerMinutes)
            if clamped != activeTriggerMinutes {
                activeTriggerMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Key.activeMinutes)
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

    /// 建议活动时长（用户自选）。可选 2 / 3 / 5：微歇 / 舒展 / 短走。
    @Published var suggestedRestMinutes: Int {
        didSet {
            let clamped = Self.clampRest(suggestedRestMinutes)
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
        activeTriggerMinutes = Self.clampActive(
            defaults.object(forKey: Key.activeMinutes) as? Int ?? 30
        )
        leaveResetMinutes = Self.clampLeave(
            defaults.object(forKey: Key.leaveMinutes) as? Int ?? 5
        )
        // 旧版 1/2/3 或联动档若不在新选项内，回落默认 2。
        let storedRest = defaults.object(forKey: Key.restMinutes) as? Int
            ?? defaults.object(forKey: "moveReminder.restMinutes.v1") as? Int
            ?? 2
        suggestedRestMinutes = Self.clampRest(storedRest)
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

    static let activeOptions = [30, 60, 90, 120]
    static let leaveOptions = [3, 5, 10]
    /// 2 微歇 · 3 舒展 · 5 短走（默认 2，负担低、易坚持）。
    static let restOptions = [2, 3, 5]

    private static func clampActive(_ v: Int) -> Int {
        activeOptions.contains(v) ? v : 30
    }

    private static func clampLeave(_ v: Int) -> Int {
        leaveOptions.contains(v) ? v : 5
    }

    private static func clampRest(_ v: Int) -> Int {
        restOptions.contains(v) ? v : 2
    }

    func restoreDefaults() {
        activeTriggerMinutes = 30
        leaveResetMinutes = 5
        suggestedRestMinutes = 2
        hapticEnabled = false
        smartAvoidEnabled = false
        clearMute()
        clearSnooze()
        AppLog.info("MoveReminder", "已恢复默认设置", [
            "active": 30,
            "rest": 2,
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
