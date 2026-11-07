import AppKit
import Combine
import Foundation

/// 久坐提醒会话：在电脑前累计 → 触阈上岛；闲置离开清零；智能避让时冻结。
@MainActor
final class MoveReminderSession: ObservableObject {
    static let shared = MoveReminderSession()

    struct Notice: Hashable, Identifiable {
        let id: String
        let activeMinutes: Int
        let restMinutes: Int
    }

    @Published private(set) var accumulatedSeconds: TimeInterval = 0
    @Published private(set) var lastIdleSeconds: TimeInterval = 0
    @Published private(set) var isPausedForAvoid: Bool = false

    private let settings = MoveReminderSettings.shared
    private var timer: Timer?
    private var started = false
    private var presentingNoticeID: String?
    /// 本轮累计起点（仅在「在场」时推进）。
    private var lastTickAt: Date?
    private var lastAvoidReason = "none"
    private var noticeObserver: AnyCancellable?

    private init() {}

    func start() {
        guard !started else {
            tick(reason: "resume")
            return
        }
        started = true
        lastTickAt = Date()
        noticeObserver = IslandNoticeCenter.shared.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                self?.handleNoticeCenterChange(payload)
            }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(reason: "tick")
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick(reason: "start")
        AppLog.info("MoveReminder", "久坐提醒会话已启动")
    }

    private func handleNoticeCenterChange(_ payload: IslandNoticePayload?) {
        guard let id = presentingNoticeID else { return }
        if payload?.id != id {
            presentingNoticeID = nil
            // 被其它通知顶掉 / 用户操作收起后清零，避免立刻再次触阈。
            resetAccumulation(reason: "noticeDismissed")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
        lastTickAt = nil
        accumulatedSeconds = 0
        dismissNoticeIfNeeded(reason: "stop")
        AppLog.info("MoveReminder", "久坐提醒会话已停止")
    }

    func snoozeTenMinutes() {
        settings.snooze(minutes: 10)
        resetAccumulation(reason: "snooze")
        dismissNoticeIfNeeded(reason: "snooze")
        fireHapticIfNeeded()
    }

    func muteForToday() {
        settings.muteForRestOfDay()
        resetAccumulation(reason: "muteToday")
        dismissNoticeIfNeeded(reason: "muteToday")
    }

    // MARK: - Tick

    private func tick(reason: String) {
        guard WidgetSettings.shared.isEnabled("builtin.moveReminder") else {
            resetAccumulation(reason: "disabled")
            dismissNoticeIfNeeded(reason: "disabled")
            lastTickAt = Date()
            return
        }

        let now = Date()
        let idle = MoveReminderIdleProbe.secondsSinceLastInput()
        lastIdleSeconds = idle

        // 离开：闲置过阈值 → 清零（并收起未处理的提醒）。
        if idle >= settings.leaveResetSeconds {
            if accumulatedSeconds > 0 || presentingNoticeID != nil {
                AppLog.info("MoveReminder", "判定已离开，计时清零", [
                    "idleSec": Int(idle),
                    "threshold": settings.leaveResetMinutes,
                    "hadAccum": Int(accumulatedSeconds),
                    "reason": reason
                ])
            }
            resetAccumulation(reason: "left")
            dismissNoticeIfNeeded(reason: "left")
            lastTickAt = now
            return
        }

        let avoid = MoveReminderAvoidProbe.evaluate(smartAvoidEnabled: settings.smartAvoidEnabled)
        if avoid.shouldPause != isPausedForAvoid || avoid.reason != lastAvoidReason {
            isPausedForAvoid = avoid.shouldPause
            lastAvoidReason = avoid.reason
            if avoid.shouldPause {
                AppLog.info("MoveReminder", "智能避让暂停累计", ["reason": avoid.reason])
            }
        }

        let muted = settings.isMutedNow(at: now)
        let snoozed = settings.isSnoozedNow(at: now)

        // 提醒展示中 / 静音 / 稍后 / 避让：不累计，但保持「在场」状态（不清零）。
        if presentingNoticeID != nil || muted || snoozed || avoid.shouldPause {
            lastTickAt = now
            return
        }

        let previous = lastTickAt ?? now
        let delta = max(0, now.timeIntervalSince(previous))
        lastTickAt = now
        // 单次 tick 上限，避免系统休眠醒来后暴涨。
        let capped = min(delta, 30)
        accumulatedSeconds += capped

        if accumulatedSeconds >= settings.activeTriggerSeconds {
            presentAlertIfNeeded()
        }
    }

    private func presentAlertIfNeeded() {
        guard presentingNoticeID == nil else { return }
        guard WidgetSettings.shared.isEnabled("builtin.moveReminder") else { return }
        guard !settings.isMutedNow(), !settings.isSnoozedNow() else { return }

        let notice = Notice(
            id: "moveReminder.\(settings.activeTriggerMinutes).\(Int(Date().timeIntervalSince1970))",
            activeMinutes: settings.activeTriggerMinutes,
            restMinutes: settings.suggestedRestMinutes
        )
        presentingNoticeID = notice.id
        IslandNoticeCenter.shared.present(.moveReminder(notice))
        fireHapticIfNeeded()
        AppLog.info("MoveReminder", "已投递久坐起身提醒", [
            "activeMinutes": notice.activeMinutes,
            "restMinutes": notice.restMinutes,
            "accumSec": Int(accumulatedSeconds)
        ])
    }

    private func resetAccumulation(reason: String) {
        if accumulatedSeconds > 0 {
            AppLog.debug("MoveReminder", "累计已清零", [
                "reason": reason,
                "was": Int(accumulatedSeconds)
            ])
        }
        accumulatedSeconds = 0
        lastTickAt = Date()
    }

    private func dismissNoticeIfNeeded(reason: String) {
        guard let id = presentingNoticeID else { return }
        presentingNoticeID = nil
        IslandNoticeCenter.shared.dismiss(id: id)
        AppLog.debug("MoveReminder", "已撤回久坐通知", ["reason": reason, "id": id])
    }

    private func fireHapticIfNeeded() {
        guard settings.hapticEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// 通知被外部 dismiss 时对齐状态（可选由卡片按钮调用后已清理）。
    func noteNoticeDismissed(id: String) {
        if presentingNoticeID == id {
            presentingNoticeID = nil
        }
    }
}
