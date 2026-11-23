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

    /// 收起岛左右待命：倒计时 / 加时 / 正计时。
    var showsCompactStandby: Bool {
        isWidgetEnabled && (phase == .running || phase == .overtime || phase == .countUp)
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
    private var isPaused = false
    /// 正计时暂停累计：墙钟结算时扣除暂停时长。
    private var pausedAccumulatedSeconds = 0
    private var pauseStartedAt: Date?
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

    /// 选时态「正计时」：从 0 纯累加，无目标时长、不自动收工。
    func startCountUpTimer() {
        if phase == .completed {
            pendingRecordID = nil
        }
        selectedPresetID = nil
        plannedSeconds = 0
        overtimeSeconds = 0
        elapsedSeconds = 0
        isPaused = false
        pausedAccumulatedSeconds = 0
        pauseStartedAt = nil
        startedAt = Date()
        sessionTitle = L10n.FocusTimer.countUpSessionTitle
        sessionKind = .countUp
        phase = .countUp
        noteDraft = ""
        startTicking()
        publishSnapshot()
        AppLog.info("FocusTimer", "开始正计时")
        IslandHaptics.play(IslandSettings.shared.hapticIntensity)
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
        isPaused = false
        pausedAccumulatedSeconds = 0
        pauseStartedAt = nil
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

    /// 正计时暂停 / 继续。
    func toggleCountUpPause() {
        guard phase == .countUp else { return }
        if isPaused {
            if let pauseStartedAt {
                pausedAccumulatedSeconds += max(0, Int(Date().timeIntervalSince(pauseStartedAt)))
            }
            pauseStartedAt = nil
            isPaused = false
            startTicking()
            AppLog.info("FocusTimer", "正计时继续", ["elapsed": elapsedSeconds])
        } else {
            isPaused = true
            pauseStartedAt = Date()
            stopTicking()
            AppLog.info("FocusTimer", "正计时暂停", ["elapsed": elapsedSeconds])
        }
        publishSnapshot()
        IslandHaptics.play(IslandSettings.shared.hapticIntensity)
    }

    func finishEarly() {
        guard phase == .running || phase == .overtime || phase == .countUp else { return }
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
        if phase == .countUp {
            guard !isPaused else { return }
            elapsedSeconds += 1
            publishSnapshot()
            return
        }
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
        let wasCountUp = phase == .countUp
        // 正计时若停在暂停态，把末段暂停并入累计，避免墙钟虚高。
        if wasCountUp, isPaused, let pauseStartedAt {
            pausedAccumulatedSeconds += max(0, Int(Date().timeIntervalSince(pauseStartedAt)))
            self.pauseStartedAt = nil
        }
        // 倒计时：归零前判断是否提前结束（钳制 elapsed 之后 remaining 恒为 0）。
        let endedEarly = wasCountUp ? false : remainingSeconds() > 0
        if !wasCountUp {
            elapsedSeconds = min(elapsedSeconds, plannedSeconds + overtimeSeconds)
        }
        isPaused = false
        // 一结束就落库；备注可稍后点「保存」写入，不点也不丢本条计时。
        pendingRecordID = finalizeRecord(note: "", endedEarly: endedEarly, isCountUp: wasCountUp)
        noteDraft = ""
        phase = .completed
        publishSnapshot()
        AppLog.warn("FocusTimer", "计时结束并已入库", [
            "reason": reason,
            "elapsed": elapsedSeconds,
            "overtime": overtimeSeconds,
            "endedEarly": endedEarly,
            "countUp": wasCountUp,
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
    private func finalizeRecord(note: String, endedEarly: Bool, isCountUp: Bool) -> UUID? {
        guard let startedAt else { return nil }
        let endedAt = Date()
        let tickSec = max(0, elapsedSeconds)
        let id = UUID()
        let record: FocusTimerRecord
        if isCountUp {
            // 正计时：计划=实际；扣暂停后的墙钟与滴答取较大值。
            var wallSec = max(0, Int(endedAt.timeIntervalSince(startedAt)) - pausedAccumulatedSeconds)
            wallSec = max(0, wallSec)
            let actualSec = max(tickSec, wallSec)
            let elapsedMin = max(1, (actualSec + 59) / 60)
            record = FocusTimerRecord(
                id: id,
                title: note,
                kind: .countUp,
                plannedMinutes: elapsedMin,
                overtimeMinutes: 0,
                elapsedMinutes: elapsedMin,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note,
                completedOnTime: true,
                endedEarly: false
            )
            AppLog.info("FocusTimer", "结算正计时工时", [
                "elapsedMin": elapsedMin,
                "wallSec": wallSec,
                "tickSec": tickSec,
                "pausedSec": pausedAccumulatedSeconds
            ])
        } else {
            let plannedMin = max(1, plannedSeconds / 60)
            let overtimeMin = overtimeSeconds / 60
            // 实际专注：优先墙钟（开始→结束）；与滴答取较大值，避免后台节流少记。
            // 提前结束绝不用计划时长顶替（10 分计划、5 分收工 → 记 5）。
            let wallSec = max(0, Int(endedAt.timeIntervalSince(startedAt)))
            let scheduleSec = plannedSeconds + overtimeSeconds
            let rawSec = max(wallSec, tickSec)
            let actualSec = endedEarly
                ? min(rawSec, max(scheduleSec - 1, 0))
                : min(rawSec, scheduleSec)
            let elapsedMin = max(1, actualSec / 60)
            record = FocusTimerRecord(
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
            AppLog.info("FocusTimer", "结算实际工时", [
                "elapsedMin": elapsedMin,
                "plannedMin": plannedMin,
                "overtimeMin": overtimeMin,
                "endedEarly": endedEarly,
                "wallSec": wallSec,
                "tickSec": tickSec
            ])
        }
        settings.appendRecord(record)
        self.startedAt = nil
        pausedAccumulatedSeconds = 0
        pauseStartedAt = nil
        return id
    }

    private func resetToPicking(reason: String) {
        stopTicking()
        phase = .picking
        plannedSeconds = 0
        overtimeSeconds = 0
        elapsedSeconds = 0
        isPaused = false
        pausedAccumulatedSeconds = 0
        pauseStartedAt = nil
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
        isPaused = false
        pausedAccumulatedSeconds = 0
        pauseStartedAt = nil
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
            case .countUp, .completed:
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
            selectedPresetID: selectedPresetID,
            isPaused: isPaused
        )
    }

    // MARK: - DEBUG 测试台快进（仅本地开发）

    #if DEBUG
    /// 一键回到选时态（测试台）。
    func debugEnterPicking() {
        cancelActiveSession(reason: "testLabEnterPicking")
        AppLog.info("FocusTimer", "测试台进入选时")
    }

    /// 一键进入计时中（不依赖真挂钟等待）。
    func debugEnterRunning(minutes: Int = 25) {
        let clamped = min(max(minutes, 1), 180)
        startTimer(minutes: clamped, title: "Lab \(clamped)m", kind: .custom)
        AppLog.info("FocusTimer", "测试台进入计时", ["minutes": clamped])
    }

    /// 一键进入正计时（可注入已过秒数，便于验收时分秒档岛宽）。
    func debugEnterCountUp(elapsedSeconds: Int = 90) {
        startCountUpTimer()
        let clamped = max(0, elapsedSeconds)
        self.elapsedSeconds = clamped
        publishSnapshot()
        AppLog.info("FocusTimer", "测试台进入正计时", ["elapsed": clamped])
    }

    /// 一键进入加时态。
    func debugEnterOvertime() {
        if phase != .running && phase != .overtime {
            debugEnterRunning(minutes: 25)
        }
        extend(byMinutes: settings.extendStepMinutes)
        AppLog.info("FocusTimer", "测试台进入加时")
    }

    /// 一键进入终局（会落库一条 Lab 记录）。
    func debugEnterCompleted() {
        if phase != .running && phase != .overtime {
            debugEnterRunning(minutes: 5)
            elapsedSeconds = max(1, plannedSeconds - 1)
        }
        complete(reason: "testLabEnterCompleted")
        AppLog.info("FocusTimer", "测试台进入终局")
    }

    /// 快进若干分钟（增加 elapsed）。倒计时 / 加时 / 正计时均可；正计时不自动收工。
    func debugAdvance(byMinutes minutes: Int) {
        let addMin = min(max(minutes, 1), 24 * 60)
        let add = addMin * 60
        if phase == .countUp {
            elapsedSeconds += add
            publishSnapshot()
            AppLog.info("FocusTimer", "测试台正计时加时", [
                "addMin": addMin,
                "elapsed": elapsedSeconds
            ])
            return
        }
        guard phase == .running || phase == .overtime else {
            AppLog.warn("FocusTimer", "测试台快进忽略：非计时态", ["phase": phase.rawValue])
            return
        }
        elapsedSeconds += add
        if remainingSeconds() <= 0 {
            complete(reason: "testLabAdvanceEnd")
        } else {
            publishSnapshot()
        }
        AppLog.info("FocusTimer", "测试台倒计时快进", [
            "addMin": addMin,
            "remain": remainingSeconds()
        ])
    }

    /// 正计时加若干小时（测试台；便于验收时分秒档岛宽）。
    func debugAdvanceCountUp(byHours hours: Int) {
        if phase != .countUp {
            debugEnterCountUp(elapsedSeconds: elapsedSeconds)
        }
        let addH = min(max(hours, 1), 24)
        debugAdvance(byMinutes: addH * 60)
    }

    /// 跳到还剩指定秒数。
    func debugJumpToRemaining(seconds: Int) {
        if phase != .running && phase != .overtime {
            debugEnterRunning(minutes: 25)
        }
        let target = max(0, seconds)
        let total = plannedSeconds + overtimeSeconds
        elapsedSeconds = max(0, total - target)
        if remainingSeconds() <= 0 {
            complete(reason: "testLabJumpRemainZero")
        } else {
            publishSnapshot()
        }
        AppLog.info("FocusTimer", "测试台跳到剩余", ["remain": remainingSeconds()])
    }

    /// 跳到结束（触发终局）。
    func debugJumpToEnd() {
        if phase != .running && phase != .overtime {
            debugEnterRunning(minutes: 5)
        }
        elapsedSeconds = plannedSeconds + overtimeSeconds
        complete(reason: "testLabJumpEnd")
        AppLog.info("FocusTimer", "测试台跳到结束")
    }

    /// 若仍在 running，加时并确保仍有剩余。
    func debugJumpIntoOvertime() {
        if phase == .completed || phase == .picking {
            debugEnterRunning(minutes: 25)
        }
        if phase == .running {
            elapsedSeconds = plannedSeconds
            extend(byMinutes: settings.extendStepMinutes)
        } else if phase == .overtime {
            publishSnapshot()
        }
        AppLog.info("FocusTimer", "测试台跳进加时", ["remain": remainingSeconds()])
    }
    #endif
}
