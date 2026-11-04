import Foundation

/// 灵动岛番茄倒计时运行态（选时 / 计时 / 顺延 / 终局）。收起待命是 running 的收起表现。
enum FocusTimerPhase: String, Equatable {
    /// 未起钟：选预设或自定义分钟。
    case picking
    /// 计时中（收起为左右待命；悬停为进行中面板）。
    case running
    /// 已加时：悬停只展示顺延面板，不再回到「进行中」。
    case overtime
    /// 时间到：填写备注并结算。
    case completed
}

/// 设置页五态预览 Tab（含「标准待命」收起样张）。
enum FocusTimerPreviewTab: String, CaseIterable, Identifiable {
    case standby
    case picking
    case running
    case overtime
    case completed

    var id: String { rawValue }

    var phase: FocusTimerPhase {
        switch self {
        case .standby: return .running
        case .picking: return .picking
        case .running: return .running
        case .overtime: return .overtime
        case .completed: return .completed
        }
    }

    var isCompact: Bool { self == .standby }
}

enum FocusTimerKind: String, Codable, Hashable {
    case preset
    case custom
    case overtimeSprint
}

struct FocusTimerPreset: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var minutes: Int
    var subtitle: String
    /// 展示色：error / primary / tertiary / secondary。
    var tint: String

    /// 默认四档：15 / 30 / 60 / 90；微调步长分别为 ±5 / ±5 / ±10 / ±20。
    static let defaults: [FocusTimerPreset] = [
        FocusTimerPreset(
            id: "sprint",
            title: L10n.FocusTimer.presetSprint,
            minutes: 15,
            subtitle: L10n.FocusTimer.presetSprintHint,
            tint: "primary"
        ),
        FocusTimerPreset(
            id: "tomato",
            title: L10n.FocusTimer.presetTomato,
            minutes: 30,
            subtitle: L10n.FocusTimer.presetTomatoHint,
            tint: "error"
        ),
        FocusTimerPreset(
            id: "deep",
            title: L10n.FocusTimer.presetDeep,
            minutes: 60,
            subtitle: L10n.FocusTimer.presetDeepHint,
            tint: "tertiary"
        ),
        FocusTimerPreset(
            id: "long",
            title: L10n.FocusTimer.presetLong,
            minutes: 90,
            subtitle: L10n.FocusTimer.presetLongHint,
            tint: "secondary"
        )
    ]

    /// 设置页分钟微调步长。
    var adjustStepMinutes: Int {
        switch id {
        case "sprint", "tomato": return 5
        case "deep": return 10
        case "long": return 20
        default:
            if minutes >= 90 { return 20 }
            if minutes >= 60 { return 10 }
            return 5
        }
    }
}

struct FocusTimerRecord: Identifiable, Equatable, Hashable {
    var id: UUID
    var title: String
    var kind: FocusTimerKind
    /// 开钟时设定的时长（不含顺延）。
    var plannedMinutes: Int
    var overtimeMinutes: Int
    /// 实际专注分钟（提前结束按已过时长；正常/顺延走完 ≈ planned+overtime）。
    var elapsedMinutes: Int
    var startedAt: Date
    var endedAt: Date
    var note: String
    var completedOnTime: Bool
    /// 倒计时未归零就结束（点「结束」/ 顺延中提前收工）。
    var endedEarly: Bool

    /// 计入「今日专注工时」等统计：按开始～结束墙钟实际分钟。
    /// 提前结束只记已过时长（10 分计划、5 分收工 → 记 5），不用计划时长顶替。
    var totalMinutes: Int {
        let wall = Int(endedAt.timeIntervalSince(startedAt) / 60)
        if wall >= 1 { return wall }
        // 不足 1 分钟：有开钟即记 1；若字段已有实际值则沿用。
        return max(1, elapsedMinutes)
    }

    var achievementPercent: Int {
        guard plannedMinutes > 0 else { return 100 }
        return Int((Double(totalMinutes) / Double(plannedMinutes) * 100).rounded())
    }

    /// 终局未填备注 / 标题为空 → 看板展示「未命名专注」并可事后补填。
    var isUntitled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension FocusTimerRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, kind, plannedMinutes, overtimeMinutes, elapsedMinutes
        case startedAt, endedAt, note, completedOnTime, endedEarly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decode(FocusTimerKind.self, forKey: .kind)
        plannedMinutes = try c.decode(Int.self, forKey: .plannedMinutes)
        overtimeMinutes = try c.decode(Int.self, forKey: .overtimeMinutes)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        note = try c.decode(String.self, forKey: .note)
        completedOnTime = try c.decode(Bool.self, forKey: .completedOnTime)
        endedEarly = try c.decodeIfPresent(Bool.self, forKey: .endedEarly) ?? false
        // 旧数据无 elapsedMinutes：按 planned+overtime 兜底。
        elapsedMinutes = try c.decodeIfPresent(Int.self, forKey: .elapsedMinutes)
            ?? (plannedMinutes + overtimeMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(kind, forKey: .kind)
        try c.encode(plannedMinutes, forKey: .plannedMinutes)
        try c.encode(overtimeMinutes, forKey: .overtimeMinutes)
        try c.encode(elapsedMinutes, forKey: .elapsedMinutes)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(note, forKey: .note)
        try c.encode(completedOnTime, forKey: .completedOnTime)
        try c.encode(endedEarly, forKey: .endedEarly)
    }
}

/// 岛面 / 预览共用的瞬时快照。
struct FocusTimerSnapshot: Equatable {
    var phase: FocusTimerPhase
    var plannedSeconds: Int
    var overtimeSeconds: Int
    var elapsedSeconds: Int
    var remainingSeconds: Int
    var noteDraft: String
    var customMinutes: Int
    var selectedPresetID: String?

    var progress: Double {
        let total = max(plannedSeconds + overtimeSeconds, 1)
        return min(1, Double(elapsedSeconds) / Double(total))
    }

    var plannedMinutes: Int { max(1, plannedSeconds / 60) }
    var overtimeMinutes: Int { overtimeSeconds / 60 }

    static let pickingPreview = FocusTimerSnapshot(
        phase: .picking,
        plannedSeconds: 15 * 60,
        overtimeSeconds: 0,
        elapsedSeconds: 0,
        remainingSeconds: 15 * 60,
        noteDraft: "",
        customMinutes: 25,
        selectedPresetID: nil
    )

    static let runningStandbyPreview = FocusTimerSnapshot(
        phase: .running,
        plannedSeconds: 30 * 60,
        overtimeSeconds: 0,
        elapsedSeconds: 6 * 60 + 18,
        remainingSeconds: 23 * 60 + 42,
        noteDraft: "",
        customMinutes: 30,
        selectedPresetID: "tomato"
    )

    static let runningExpandedPreview = FocusTimerSnapshot(
        phase: .running,
        plannedSeconds: 30 * 60,
        overtimeSeconds: 0,
        elapsedSeconds: 6 * 60 + 18,
        remainingSeconds: 23 * 60 + 42,
        noteDraft: "",
        customMinutes: 30,
        selectedPresetID: "tomato"
    )

    static let overtimePreview = FocusTimerSnapshot(
        phase: .overtime,
        plannedSeconds: 30 * 60,
        overtimeSeconds: 10 * 60,
        elapsedSeconds: 35 * 60 + 30,
        remainingSeconds: 4 * 60 + 30,
        noteDraft: "",
        customMinutes: 30,
        selectedPresetID: "tomato"
    )

    static let completedPreview = FocusTimerSnapshot(
        phase: .completed,
        plannedSeconds: 30 * 60,
        overtimeSeconds: 10 * 60,
        elapsedSeconds: 40 * 60,
        remainingSeconds: 0,
        noteDraft: L10n.FocusTimer.previewNote,
        customMinutes: 30,
        selectedPresetID: "tomato"
    )
}

enum FocusTimerFormatting {
    static func clock(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    static func compactDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }
}
