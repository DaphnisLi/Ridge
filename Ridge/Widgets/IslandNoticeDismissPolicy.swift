import Foundation

/// 瞬时通知自动收起 / 结束后是否收岛——纯策略，供单测穷举。
enum IslandNoticeAutoDismissPolicy {
    /// 非会议类瞬时 tip 统一停留时长。
    static let standardNanoseconds: UInt64 = 3_000_000_000
    /// 悬停 / 设置挡住时的轮询间隔。
    static let pollNanoseconds: UInt64 = 100_000_000

    /// 计时开始前：设置挡住且 tip 不能在设置中展开 → 先等设置关。
    static func shouldWaitForSettingsUnblock(
        expandsDuringSettingsSession: Bool,
        settingsBlocksExpand: Bool
    ) -> Bool {
        !expandsDuringSettingsSession && settingsBlocksExpand
    }

    /// 时长到后：悬停保活则继续等指针离开。
    static func shouldWaitForHoverEnd(holdWhileHovering: Bool, isHovering: Bool) -> Bool {
        holdWhileHovering && isHovering
    }

    /// payload 声明的自动收时长；无则手动收。
    static func nanoseconds(for payload: IslandNoticePayload) -> UInt64? {
        payload.autoDismissNanoseconds
    }
}

/// 通知撤完后是否因悬停保展开（避免空双翼岛挂着）。
enum IslandNoticeEndCollapsePolicy {
    /// `noticeFullyGone`：槽内无 tip 且已不在瞬时通知页。
    static func shouldKeepExpandedAfterNoticeEnd(
        hovering: Bool,
        noticeFullyGone: Bool,
        allowsHoverExpand: Bool
    ) -> Bool {
        hovering && noticeFullyGone && allowsHoverExpand
    }

    static func isNoticeFullyGone(current: IslandNoticePayload?, isTransientNoticePage: Bool) -> Bool {
        current == nil && !isTransientNoticePage
    }
}
