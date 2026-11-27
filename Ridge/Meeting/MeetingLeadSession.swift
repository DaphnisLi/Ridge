import AppKit
import Foundation

/// 会前提示会话：会议 widget 写入快照，岛通知卡只读展示（不占内容分页）。
/// 倒计时与入会由本会话自持，不依赖 tip widget 是否仍存活。
@MainActor
final class MeetingLeadSession: ObservableObject {
    static let shared = MeetingLeadSession()

    struct Snapshot: Equatable {
        let meetingID: String
        let title: String
        let startDate: Date
        let endDate: Date
        /// 距开始的秒数；已开始为 ≤0。由 tick 刷新。
        let secondsToStart: TimeInterval
        let showJoin: Bool
        let showAuth: Bool
        /// 入会深链 / 网页回退；点「进入」直接打开，不经 widget weak self。
        let joinOpenURL: URL?
        let joinSourceURL: URL?
        let joinPlatform: String?

        var urgency: MeetingLeadUrgency {
            MeetingLeadUrgency.resolve(secondsToStart: secondsToStart)
        }
    }

    @Published private(set) var snapshot: Snapshot?

    /// 用户已点入会的会议 id（会话级权威；勿只存在 widget weak self 上）。
    private(set) var dismissedAfterJoinID: String?

    /// 入会成功后通知 widget 清 latch（可选）。
    var onJoined: ((String) -> Void)?
    /// 保留窗口结束 / 入会后改选下一场。
    var onTipExpired: ((String) -> Void)?
    var onRequestAuth: (() -> Void)?

    /// 测试可注入；默认 `NSWorkspace.open`。
    var openURLHandler: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    private var tick: Timer?

    private init() {}

    /// 单测复位；生产勿调用。
    func resetForTests() {
        stopTicking()
        snapshot = nil
        dismissedAfterJoinID = nil
        onJoined = nil
        onTipExpired = nil
        onRequestAuth = nil
        openURLHandler = { NSWorkspace.shared.open($0) }
    }

    #if DEBUG
    /// 测试台：不写日历，直接投递指定紧迫度样张到真岛。
    func debugPresentSample(urgency: MeetingLeadUrgency) {
        let seconds: TimeInterval
        let title: String
        switch urgency {
        case .relaxed:
            seconds = 9 * 60 + 42
            title = L10n.Meeting.previewSampleTitleRelaxed
        case .warning:
            seconds = 4 * 60 + 30
            title = L10n.Meeting.previewSampleTitleWarning
        case .critical:
            seconds = 1 * 60 + 15
            title = L10n.Meeting.previewSampleTitleCritical
        }
        let id = "lab.meeting.\(urgency.rawValue).\(UUID().uuidString.prefix(6))"
        let start = Date().addingTimeInterval(seconds)
        publish(
            Snapshot(
                meetingID: id,
                title: title,
                startDate: start,
                endDate: start.addingTimeInterval(30 * 60),
                secondsToStart: seconds,
                showJoin: true,
                showAuth: false,
                joinOpenURL: URL(string: "https://zoom.us/j/123456789"),
                joinSourceURL: URL(string: "https://zoom.us/j/123456789"),
                joinPlatform: MeetingPlatform.zoom.rawValue
            ),
            reason: "testLab.\(urgency.rawValue)"
        )
        AppLog.info("Meeting", "测试台已投递会前样张", [
            "urgency": urgency.rawValue,
            "secToStart": Int(seconds)
        ])
    }
    #endif

    func clearDismissedAfterJoinIfAbsent(from meetingIDs: Set<String>) {
        guard let dismissed = dismissedAfterJoinID,
              !meetingIDs.contains(dismissed)
        else { return }
        AppLog.debug("Meeting", "已入会场次已离开列表，清除 dismissed", [
            "meeting": String(dismissed.prefix(8))
        ])
        dismissedAfterJoinID = nil
    }

    func publish(_ next: Snapshot?, reason: String) {
        let previous = snapshot
        // 已入会场次禁止再 present（防 widget tick / 改选竞态把 tip 贴回来）。
        // 契约：`LockedInvariants.Meeting.shouldRejectRepublish`。
        if let next,
           LockedInvariants.Meeting.shouldRejectRepublish(
               meetingID: next.meetingID,
               dismissedAfterJoinID: dismissedAfterJoinID
           )
        {
            AppLog.warn("Meeting", "拒绝再次投递已入会场次", [
                "reason": reason,
                "meeting": String(next.meetingID.prefix(8))
            ])
            if previous?.meetingID == next.meetingID {
                snapshot = nil
                stopTicking()
                IslandNoticeCenter.shared.dismiss(id: "meeting.lead.\(next.meetingID)")
            }
            return
        }
        guard previous != next else { return }
        snapshot = next
        if let next {
            let noticeID = "meeting.lead.\(next.meetingID)"
            // 同一场会每秒刷新倒计时：只更新快照，勿反复 present 造成闪动。
            let alreadyShowing = IslandNoticeCenter.shared.current?.id == noticeID
            if !alreadyShowing {
                IslandNoticeCenter.shared.present(.meetingLead(meetingID: next.meetingID))
            }
            ensureTicking()
            if previous?.meetingID != next.meetingID || previous?.urgency != next.urgency {
                AppLog.info("Meeting", alreadyShowing ? "会前提示紧迫度已更新" : "会前提示已投递", [
                    "reason": reason,
                    "meeting": String(next.meetingID.prefix(8)),
                    "join": next.showJoin,
                    "hasJoinURL": next.joinOpenURL != nil,
                    "urgency": next.urgency.rawValue,
                    "secToStart": Int(next.secondsToStart)
                ])
            }
        } else if previous?.meetingID != nil {
            stopTicking()
            if let previousID = previous?.meetingID {
                IslandNoticeCenter.shared.dismiss(id: "meeting.lead.\(previousID)")
            }
            AppLog.info("Meeting", "会前提示已清除", ["reason": reason])
        }
    }

    func joinFromNotice() {
        AppLog.warn("Meeting", "通知卡点击入会", [
            "hasSnapshot": snapshot != nil,
            "hasJoinURL": snapshot?.joinOpenURL != nil,
            "showJoin": snapshot?.showJoin ?? false
        ])
        guard let snap = snapshot else {
            AppLog.warn("Meeting", "Join 失败：无快照")
            return
        }
        guard snap.showJoin, let openURL = snap.joinOpenURL else {
            AppLog.warn("Meeting", "Join 失败：无链接", [
                "meeting": String(snap.meetingID.prefix(8)),
                "showJoin": snap.showJoin
            ])
            return
        }

        var opened = openURLHandler(openURL)
        if !opened, let source = snap.joinSourceURL, source != openURL {
            opened = openURLHandler(source)
            AppLog.warn("Meeting", "deep link 失败，回退网页链接", [
                "platform": snap.joinPlatform ?? "unknown"
            ])
        }
        AppLog.warn("Meeting", "点击 Join", [
            "platform": snap.joinPlatform ?? "unknown",
            "opened": opened,
            "meeting": String(snap.meetingID.prefix(8))
        ])

        let meetingID = snap.meetingID
        // 会话级先打标（不依赖 widget weak self），再撤 tip，再改选。
        dismissedAfterJoinID = meetingID
        onJoined?(meetingID)
        publish(nil, reason: "joined")
        onTipExpired?("joinedAdvance")
        if opened {
            AppLog.info("Meeting", "入会成功，已撤回会前提示", [
                "meeting": String(meetingID.prefix(8)),
                "dismissed": dismissedAfterJoinID ?? ""
            ])
        } else {
            AppLog.warn("Meeting", "入会打开失败仍撤回提示", [
                "meeting": String(meetingID.prefix(8)),
                "platform": snap.joinPlatform ?? "unknown",
                "dismissed": dismissedAfterJoinID ?? ""
            ])
        }
    }

    func requestAuthFromNotice() {
        AppLog.info("Meeting", "通知卡点击授权")
        onRequestAuth?()
    }

    // MARK: - Countdown tick

    private func ensureTicking() {
        guard tick == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCountdown()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
        AppLog.debug("Meeting", "会前提示倒计时已启动")
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }

    private func tickCountdown() {
        guard let current = snapshot else {
            stopTicking()
            return
        }
        let now = Date()
        let secondsToEnd = current.endDate.timeIntervalSince(now)
        let seconds = current.startDate.timeIntervalSince(now)
        // 日程结束，或超过「开始后保留」策略：清提示（widget 可能已 reap）。
        if secondsToEnd <= 0 {
            AppLog.info("Meeting", "会前提示：日程已结束，自动清除")
            publish(nil, reason: "leadTickEnded")
            onTipExpired?("leadTickEnded")
            return
        }
        if !MeetingSettings.shared.shouldRetainLeadTip(
            secondsToStart: seconds,
            secondsToEnd: secondsToEnd
        ) {
            AppLog.info("Meeting", "会前提示：已过开始后保留窗口，自动清除", [
                "mode": MeetingSettings.shared.tipDismissMode.rawValue,
                "minutes": MeetingSettings.shared.tipDismissMinutes,
                "secToStart": Int(seconds)
            ])
            publish(nil, reason: "leadTickGraceExpired")
            onTipExpired?("leadTickGraceExpired")
            return
        }
        let next = Snapshot(
            meetingID: current.meetingID,
            title: current.title,
            startDate: current.startDate,
            endDate: current.endDate,
            secondsToStart: seconds,
            showJoin: current.showJoin,
            showAuth: current.showAuth,
            joinOpenURL: current.joinOpenURL,
            joinSourceURL: current.joinSourceURL,
            joinPlatform: current.joinPlatform
        )
        guard next != current else { return }
        snapshot = next
        // 紧迫度跳档时打一条日志，便于验收绿→琥珀→红。
        if next.urgency != current.urgency {
            AppLog.info("Meeting", "会前提示紧迫度已跳档", [
                "from": current.urgency.rawValue,
                "to": next.urgency.rawValue,
                "secToStart": Int(seconds)
            ])
        }
    }
}
