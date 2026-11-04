import AppKit
import Combine
import Foundation

/// 番茄倒计时会话：五态切换、滴答、历史结算。岛 / 设置只读 `snapshot`。
@MainActor
final class FocusTimerSession: ObservableObject {
    static let shared = FocusTimerSession()

    @Published private(set) var phase: FocusTimerPhase = .picking
    @Published private(set) var snapshot: FocusTimerSnapshot = .pickingPreview
    @Published var noteDraft: String = ""
    @Published var customMinutes: Int = 25
    @Published var selectedPresetID: String? = nil

    /// 小组件是否启用（由 Widget 同步）。启用且空闲时保持选时态上岛。
    @Published private(set) var isWidgetEnabled = false

    /// 收起岛左右待命：仅计时 / 顺延中。
    var showsCompactStandby: Bool {
        isWidgetEnabled && (phase == .running || phase == .overtime)
    }

    /// 需要争夺岛展示。
    var wantsIslandDisplay: Bool {
        isWidgetEnabled
    }

    private let settings = FocusTimerSettings.shared
    private var tick: Timer?
    private var plannedSeconds = 0
    private var overtimeSeconds = 0
    private var elapsedSeconds = 0
    private var startedAt: Date?
    private var sessionTitle: String = ""
    private var sessionKind: FocusTimerKind = .preset
    /// 终局已落库的记录 id；「保存」只把备注写回这条，不再二次建档。
    private var pendingRecordID: UUID?
    private var observers: Set<AnyCancellable> = []

    private init() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.publishSnapshot()
            }
            .store(in: &observers)
        publishSnapshot()
    }

    func setWidgetEnabled(_ enabled: Bool) {
        guard isWidgetEnabled != enabled else { return }
        isWidgetEnabled = enabled
        AppLog.info("FocusTimer", "小组件开关", ["enabled": enabled, "phase": phase.rawValue])
        if !enabled {
            cancelActiveSession(reason: "widgetDisabled")
        } else if phase == .picking {
            publishSnapshot()
        }
    }

    // MARK: - Actions

    /// 点预设档位：立刻按该档起钟（不经过自定义输入）。
    func selectPreset(_ preset: FocusTimerPreset) {
        selectedPresetID = preset.id
        customMinutes = preset.minutes
        AppLog.info("FocusTimer", "预设一键起钟", ["id": preset.id, "minutes": preset.minutes])
        startTimer(minutes: preset.minutes, title: preset.title, kind: .preset)
    }

    /// 仅更新自定义分钟草稿；不起钟。
    func setCustomMinutes(_ minutes: Int) {
        customMinutes = min(max(minutes, 1), 180)
        selectedPresetID = nil
        publishSnapshot()
        AppLog.debug("FocusTimer", "自定义分钟草稿", ["minutes": customMinutes])
    }

    /// 自定义「开始计时」：按当前草稿起钟。
    func startCustomTimer() {
        selectedPresetID = nil
        AppLog.info("FocusTimer", "自定义开始计时", ["minutes": customMinutes])
        startTimer(minutes: customMinutes, title: L10n.FocusTimer.customSessionTitle, kind: .custom)
    }

    func startTimer(minutes: Int? = nil, title: String? = nil, kind: FocusTimerKind? = nil) {
        // 上一轮终局若未点保存，记录已在 complete 时入库；清掉待写备注态再开新钟。
        if phase == .completed {
            pendingRecordID = nil
        }
        let mins = minutes ?? customMinutes
        let clamped = min(max(mins, 1), 180)
        let preset = settings.presets.first { $0.id == selectedPresetID }
        plannedSeconds = clamped * 60
        overtimeSeconds = 0
        elapsedSeconds = 0
        startedAt = Date()
        sessionTitle = title
            ?? preset?.title
            ?? L10n.FocusTimer.customSessionTitle
        sessionKind = kind ?? (selectedPresetID == nil ? .custom : .preset)
        phase = .running
        noteDraft = ""
        startTicking()
        publishSnapshot()
        AppLog.info("FocusTimer", "开始计时", [
            "minutes": clamped,
            "kind": sessionKind.rawValue
        ])
        IslandHaptics.play(IslandSettings.shared.hapticIntensity)
    }

    func extend(byMinutes minutes: Int? = nil) {
        guard phase == .running || phase == .overtime else { return }
        let step = minutes ?? settings.extendStepMinutes
        let add = min(max(step, 1), 30) * 60
        overtimeSeconds += add
        phase = .overtime
        publishSnapshot()
        AppLog.info("FocusTimer", "顺延加时", [
            "addMinutes": add / 60,
            "overtimeTotal": overtimeSeconds / 60,
            "remaining": remainingSeconds()
        ])
        IslandHaptics.play(IslandSettings.shared.hapticIntensity)
    }

    func finishEarly() {
        guard phase == .running || phase == .overtime else { return }
        complete(reason: "finishEarly")
    }

    /// 保存用户填入的备注文案（计时记录在结束时已入库）。
    func saveCompletion(note: String?) {
        guard phase == .completed else { return }
        let trimmed = (note ?? noteDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        noteDraft = trimmed
        if let id = pendingRecordID, !trimmed.isEmpty {
            settings.updateRecordTitle(id: id, title: trimmed)
            AppLog.info("FocusTimer", "终局备注已保存", [
                "id": String(id.uuidString.prefix(8)),
                "len": trimmed.count
            ])
        } else {
            AppLog.info("FocusTimer", "终局确认（无备注）", [
                "hasPending": pendingRecordID != nil
            ])
        }
        pendingRecordID = nil
        resetToPicking(reason: "noteSaved")
    }

    /// 收起 / 离开终局：不丢记录（结束时已落库），只回到选时。
    func dismissCompletion() {
        guard phase == .completed else { return }
        AppLog.info("FocusTimer", "离开终局，保留已入库记录", [
            "id": pendingRecordID.map { String($0.uuidString.prefix(8)) } ?? "nil",
            "hadNote": !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ])
        pendingRecordID = nil
        resetToPicking(reason: "dismissed")
    }

    // MARK: - Tick

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }

    private func handleTick() {
        guard phase == .running || phase == .overtime else { return }
        elapsedSeconds += 1
        if remainingSeconds() <= 0 {
            complete(reason: "timerEnded")
            return
        }
        publishSnapshot()
    }

    private func remainingSeconds() -> Int {
        max(0, plannedSeconds + overtimeSeconds - elapsedSeconds)
    }

    private func complete(reason: String) {
        stopTicking()
        // 归零前判断是否提前结束（钳制 elapsed 之后 remaining 恒为 0）。
        let endedEarly = remainingSeconds() > 0
        elapsedSeconds = min(elapsedSeconds, plannedSeconds + overtimeSeconds)
        // 一结束就落库；备注可稍后点「保存」写入，不点也不丢本条计时。
        pendingRecordID = finalizeRecord(note: "", endedEarly: endedEarly)
        noteDraft = ""
        phase = .completed
        publishSnapshot()
        AppLog.warn("FocusTimer", "计时结束并已入库", [
            "reason": reason,
            "elapsed": elapsedSeconds,
            "overtime": overtimeSeconds,
            "endedEarly": endedEarly,
            "id": pendingRecordID.map { String($0.uuidString.prefix(8)) } ?? "nil"
        ])
        IslandHaptics.play(IslandSettings.shared.hapticIntensity)
        // 按时 / 提前结束都要切回番茄页并展开，否则停在其它页时看不到命名框。
        WidgetRuntime.shared.revealPage(
            FocusTimerWidget.manifest.id,
            reason: "focusTimerComplete"
        )
        IslandController.shared?.expand(reason: "focusTimerComplete")
        // 展开后再强制终局画布，避免可点区停在进行中 ~80pt，备注落在框外点不着。
        IslandController.shared?.applyFocusTimerCompletedLayout(reason: "focusTimerCompleteLayout")
    }

    @discardableResult
    private func finalizeRecord(note: String, endedEarly: Bool) -> UUID? {
        guard let startedAt else { return nil }
        let plannedMin = max(1, plannedSeconds / 60)
        let overtimeMin = overtimeSeconds / 60
        let endedAt = Date()
        // 实际专注：优先墙钟（开始→结束）；与滴答取较大值，避免后台节流少记。
        // 提前结束绝不用计划时长顶替（10 分计划、5 分收工 → 记 5）。
        let wallSec = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        let tickSec = max(0, elapsedSeconds)
        let scheduleSec = plannedSeconds + overtimeSeconds
        let rawSec = max(wallSec, tickSec)
        let actualSec = endedEarly
            ? min(rawSec, max(scheduleSec - 1, 0))
            : min(rawSec, scheduleSec)
        let elapsedMin = max(1, actualSec / 60)
        let id = UUID()
        let record = FocusTimerRecord(
            id: id,
            // 备注为空则记为未命名，设置看板可事后补填；不再用预设名顶替。
            title: note,
            kind: overtimeMin > 0 ? .overtimeSprint : sessionKind,
            plannedMinutes: plannedMin,
            overtimeMinutes: overtimeMin,
            elapsedMinutes: elapsedMin,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note,
            // 提前结束不算「按时」。
            completedOnTime: !endedEarly && overtimeMin == 0,
            endedEarly: endedEarly
        )
        settings.appendRecord(record)
        AppLog.info("FocusTimer", "结算实际工时", [
            "elapsedMin": elapsedMin,
            "plannedMin": plannedMin,
            "overtimeMin": overtimeMin,
            "endedEarly": endedEarly,
            "wallSec": wallSec,
            "tickSec": tickSec
        ])
        self.startedAt = nil
        return id
    }

    private func resetToPicking(reason: String) {
        stopTicking()
        phase = .picking
        plannedSeconds = 0
        overtimeSeconds = 0
        elapsedSeconds = 0
        startedAt = nil
        pendingRecordID = nil
        noteDraft = ""
        publishSnapshot()
        AppLog.info("FocusTimer", "回到选时态", ["reason": reason])
    }

    private func cancelActiveSession(reason: String) {
        // 终局记录已入库则只离开终局；进行中取消不写历史。
        if phase == .completed {
            dismissCompletion()
            AppLog.warn("FocusTimer", "取消会话（终局已入库）", ["reason": reason])
            return
        }
        stopTicking()
        phase = .picking
        plannedSeconds = 0
        overtimeSeconds = 0
        elapsedSeconds = 0
        startedAt = nil
        pendingRecordID = nil
        noteDraft = ""
        publishSnapshot()
        AppLog.warn("FocusTimer", "取消会话", ["reason": reason])
    }

    private func publishSnapshot() {
        let remaining: Int = {
            switch phase {
            case .picking:
                return customMinutes * 60
            case .running, .overtime:
                return remainingSeconds()
            case .completed:
                return 0
            }
        }()
        snapshot = FocusTimerSnapshot(
            phase: phase,
            plannedSeconds: phase == .picking ? customMinutes * 60 : plannedSeconds,
            overtimeSeconds: overtimeSeconds,
            elapsedSeconds: elapsedSeconds,
            remainingSeconds: remaining,
            noteDraft: noteDraft,
            customMinutes: customMinutes,
            selectedPresetID: selectedPresetID
        )
    }
}
