import Foundation

/// 从多场未结束会议中选出当前应上岛的会前提示目标。
/// 第一场提示关掉（开始后保留窗口结束 / 已入会）后，应立刻考虑第二场。
enum MeetingLeadTipSelector {
    struct Input {
        var now: Date
        var leadSeconds: TimeInterval
        var tipDismissMode: MeetingTipDismissMode
        var tipDismissMinutes: Int
        var dismissedAfterJoinID: String?
        var latchedMeetingID: String?
    }

    /// 是否仍应保留 tip（已进入 lead 后的开始后策略；纯函数，可供单测）。
    static func shouldRetain(
        mode: MeetingTipDismissMode,
        minutes: Int,
        secondsToStart: TimeInterval,
        secondsToEnd: TimeInterval
    ) -> Bool {
        guard secondsToEnd > 0 else { return false }
        if secondsToStart > 0 { return true }
        switch mode {
        case .atStart:
            return false
        case .afterMinutes:
            return secondsToStart > -TimeInterval(minutes * 60)
        case .untilEnd:
            return true
        }
    }

    /// 是否仍处于可展示窗口（含开始后保留策略）。
    static func isInTipWindow(
        startDate: Date,
        endDate: Date,
        now: Date,
        leadSeconds: TimeInterval,
        tipDismissMode: MeetingTipDismissMode,
        tipDismissMinutes: Int
    ) -> Bool {
        let secondsToEnd = endDate.timeIntervalSince(now)
        guard secondsToEnd > 0 else { return false }
        let secondsToStart = startDate.timeIntervalSince(now)
        guard secondsToStart <= leadSeconds else { return false }
        return shouldRetain(
            mode: tipDismissMode,
            minutes: tipDismissMinutes,
            secondsToStart: secondsToStart,
            secondsToEnd: secondsToEnd
        )
    }

    /// 选出应提示的会议；优先继续 latched，否则按开始时间取第一场仍在窗口内的。
    static func select(
        from meetings: [MeetingEvent],
        input: Input
    ) -> (meeting: MeetingEvent, shouldLatch: Bool)? {
        let dismissed = input.dismissedAfterJoinID

        if let latchedID = input.latchedMeetingID,
           let latched = meetings.first(where: { $0.id == latchedID }),
           latched.id != dismissed,
           isInTipWindow(
               startDate: latched.startDate,
               endDate: latched.endDate,
               now: input.now,
               leadSeconds: input.leadSeconds,
               tipDismissMode: input.tipDismissMode,
               tipDismissMinutes: input.tipDismissMinutes
           )
        {
            return (latched, true)
        }

        for meeting in meetings {
            if meeting.id == dismissed { continue }
            if isInTipWindow(
                startDate: meeting.startDate,
                endDate: meeting.endDate,
                now: input.now,
                leadSeconds: input.leadSeconds,
                tipDismissMode: input.tipDismissMode,
                tipDismissMinutes: input.tipDismissMinutes
            ) {
                return (meeting, true)
            }
        }
        return nil
    }
}
