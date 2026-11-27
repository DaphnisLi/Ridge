import Foundation

/// 瞬时通知自动收起 / 结束后是否收岛——调用入口；固定契约在 `LockedInvariants.Notice`。
enum IslandNoticeAutoDismissPolicy {
    /// 非会议类瞬时 tip 统一停留时长。
    static let standardNanoseconds = LockedInvariants.Notice.standardDisplayNanoseconds
    /// 「已复制」圆岛：入场 + 定格（`IslandChrome.notchRightOrbAutoDismissNanoseconds`），勿再等 3s。
    static var copiedNoticeNanoseconds: UInt64 {
        IslandChrome.notchRightOrbAutoDismissNanoseconds
    }
    /// 悬停 / 设置挡住时的轮询间隔。
    static let pollNanoseconds = LockedInvariants.Notice.pollNanoseconds

    static func shouldWaitForSettingsUnblock(
        expandsDuringSettingsSession: Bool,
        settingsBlocksExpand: Bool
    ) -> Bool {
        LockedInvariants.Notice.shouldWaitForSettingsUnblock(
            expandsDuringSettingsSession: expandsDuringSettingsSession,
            settingsBlocksExpand: settingsBlocksExpand
        )
    }

    static func shouldWaitForHoverEnd(holdWhileHovering: Bool, isHovering: Bool) -> Bool {
        LockedInvariants.Notice.shouldWaitForHoverEnd(
            holdWhileHovering: holdWhileHovering,
            isHovering: isHovering
        )
    }

    static func nanoseconds(for payload: IslandNoticePayload) -> UInt64? {
        payload.autoDismissNanoseconds
    }

    static func shouldDismissNow(
        expandsDuringSettingsSession: Bool,
        settingsBlocksExpand: Bool,
        holdWhileHovering: Bool,
        isHovering: Bool,
        elapsedNanoseconds: UInt64,
        displayNanoseconds: UInt64
    ) -> Bool {
        LockedInvariants.Notice.shouldDismissNow(
            expandsDuringSettingsSession: expandsDuringSettingsSession,
            settingsBlocksExpand: settingsBlocksExpand,
            holdWhileHovering: holdWhileHovering,
            isHovering: isHovering,
            elapsedNanoseconds: elapsedNanoseconds,
            displayNanoseconds: displayNanoseconds
        )
    }
}

/// 通知撤完后是否因悬停保展开（避免空双翼岛挂着）。
enum IslandNoticeEndCollapsePolicy {
    static func shouldKeepExpandedAfterNoticeEnd(
        hovering: Bool,
        noticeFullyGone: Bool,
        allowsHoverExpand: Bool
    ) -> Bool {
        LockedInvariants.Notice.shouldKeepExpandedAfterNoticeEnd(
            hovering: hovering,
            noticeFullyGone: noticeFullyGone,
            allowsHoverExpand: allowsHoverExpand
        )
    }

    static func isNoticeFullyGone(current: IslandNoticePayload?, isTransientNoticePage: Bool) -> Bool {
        LockedInvariants.Notice.isNoticeFullyGone(
            currentIsNil: current == nil,
            isTransientNoticePage: isTransientNoticePage
        )
    }
}
