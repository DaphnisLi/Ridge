import Combine
import Foundation

/// 番茄倒计时用户设置：预设档位、加时步长、历史。
@MainActor
final class FocusTimerSettings: ObservableObject {
    static let shared = FocusTimerSettings()

    enum Defaults {
        static let extendStepMinutes = 5
        /// 顺延步长可选档；非法持久化值回落到默认 5。
        static let extendStepOptions = [5, 10, 15]
        /// 今日专注概览基准时长（分钟）。
        static let dailyGoalMinutes = 120
    }

    private enum Key {
        /// v2：默认档位改为 15 / 30 / 60 / 90。
        static let presets = "focusTimer.presets.v2"
        static let extendStep = "focusTimer.extendStepMinutes"
        static let history = "focusTimer.history.v1"
    }

    @Published var presets: [FocusTimerPreset] {
        didSet { persistPresets() }
    }

    @Published var extendStepMinutes: Int {
        didSet {
            let normalized = Self.normalizedExtendStep(extendStepMinutes)
            if normalized != extendStepMinutes {
                extendStepMinutes = normalized
                return
            }
            UserDefaults.standard.set(extendStepMinutes, forKey: Key.extendStep)
        }
    }

    private static func normalizedExtendStep(_ raw: Int) -> Int {
        Defaults.extendStepOptions.contains(raw) ? raw : Defaults.extendStepMinutes
    }

    @Published private(set) var history: [FocusTimerRecord] {
        didSet { persistHistory() }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.presets),
           let decoded = try? JSONDecoder().decode([FocusTimerPreset].self, from: data),
           !decoded.isEmpty
        {
            presets = decoded
        } else {
            presets = FocusTimerPreset.defaults
        }
        let rawExtend = defaults.object(forKey: Key.extendStep) as? Int ?? Defaults.extendStepMinutes
        extendStepMinutes = Self.normalizedExtendStep(rawExtend)
        if let data = defaults.data(forKey: Key.history),
           let decoded = try? JSONDecoder().decode([FocusTimerRecord].self, from: data)
        {
            history = decoded
        } else {
            history = []
        }
    }

    func updatePreset(_ preset: FocusTimerPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        AppLog.info("FocusTimer", "更新预设", ["id": preset.id, "minutes": preset.minutes])
    }

    /// 档位分钟微调；钳制在 5…180。
    func bumpPresetMinutes(id: String, delta: Int) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        var next = presets[idx]
        let clamped = min(max(next.minutes + delta, 5), 180)
        guard clamped != next.minutes else { return }
        next.minutes = clamped
        presets[idx] = next
        AppLog.info("FocusTimer", "微调预设分钟", [
            "id": id,
            "delta": delta,
            "minutes": clamped
        ])
    }

    func appendRecord(_ record: FocusTimerRecord) {
        var next = history
        next.insert(record, at: 0)
        if next.count > 80 { next = Array(next.prefix(80)) }
        history = next
        AppLog.info("FocusTimer", "写入历史", [
            "kind": record.kind.rawValue,
            "planned": record.plannedMinutes,
            "overtime": record.overtimeMinutes,
            "elapsed": record.elapsedMinutes,
            "untitled": record.isUntitled
        ])
    }

    func updateRecordTitle(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = history.firstIndex(where: { $0.id == id })
        else { return }
        history[idx].title = trimmed
        history[idx].note = trimmed
        AppLog.info("FocusTimer", "补填事项名称", [
            "id": String(id.uuidString.prefix(8)),
            "len": trimmed.count
        ])
    }

    func clearTodayHistory() {
        let cal = Calendar.current
        history = history.filter { !cal.isDateInToday($0.endedAt) }
        AppLog.info("FocusTimer", "已清空今日历史")
    }

    func clearAllHistory() {
        guard !history.isEmpty else { return }
        history = []
        AppLog.info("FocusTimer", "已清空全部计时历史")
    }

    func restoreDefaults() {
        presets = FocusTimerPreset.defaults
        extendStepMinutes = Defaults.extendStepMinutes
        AppLog.info("FocusTimer", "已恢复默认设置")
    }

    // MARK: - Frequent titles

    /// 从历史记录统计常用标题（次数优先，其次最近使用），供补填快捷标签。
    func frequentTitles(limit: Int = 5, excluding id: UUID? = nil) -> [String] {
        var tallies: [String: (count: Int, lastUsed: Date)] = [:]
        for record in history {
            if let id, record.id == id { continue }
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let prev = tallies[title]
            tallies[title] = (
                (prev?.count ?? 0) + 1,
                max(prev?.lastUsed ?? .distantPast, record.endedAt)
            )
        }
        let ranked = tallies.sorted { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count > rhs.value.count
            }
            return lhs.value.lastUsed > rhs.value.lastUsed
        }
        return Array(ranked.prefix(max(0, limit)).map(\.key))
    }

    // MARK: - Today stats

    var todayRecords: [FocusTimerRecord] {
        let cal = Calendar.current
        return history.filter { cal.isDateInToday($0.endedAt) }
    }

    var todayCount: Int { todayRecords.count }

    var todayFocusMinutes: Int {
        todayRecords.reduce(0) { $0 + $1.totalMinutes }
    }

    var todayOvertimeMinutes: Int {
        todayRecords.reduce(0) { $0 + $1.overtimeMinutes }
    }

    var todayOvertimeRatePercent: Double {
        let planned = todayRecords.reduce(0) { $0 + $1.plannedMinutes }
        guard planned > 0 else { return 0 }
        return Double(todayFocusMinutes) / Double(planned) * 100
    }

    /// 准时完成率（0…100）；无记录时为 0。
    var todayOnTimeRatePercent: Int {
        let records = todayRecords
        guard !records.isEmpty else { return 0 }
        let onTime = records.filter(\.completedOnTime).count
        return Int((Double(onTime) / Double(records.count) * 100).rounded())
    }

    /// 相对计划时长的顺延溢出比（0…）；无计划时为 0。
    var todayOverflowPercent: Double {
        let planned = todayRecords.reduce(0) { $0 + $1.plannedMinutes }
        guard planned > 0 else { return 0 }
        return Double(todayOvertimeMinutes) / Double(planned) * 100
    }

    var dailyGoalMinutes: Int { Defaults.dailyGoalMinutes }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Key.presets)
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Key.history)
    }
}
