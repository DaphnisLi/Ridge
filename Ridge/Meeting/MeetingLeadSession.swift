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

    /// 入会成功后通知 widget 记 dismissed（可选）。
    var onJoined: ((String) -> Void)?
    var onRequestAuth: (() -> Void)?

    private var tick: Timer?

    private init() {}

    func publish(_ next: Snapshot?, reason: String) {
        let previous = snapshot
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

        var opened = NSWorkspace.shared.open(openURL)
        if !opened, let source = snap.joinSourceURL, source != openURL {
            opened = NSWorkspace.shared.open(source)
            AppLog.warn("Meeting", "deep link 失败，回退网页链接", [
                "platform": snap.joinPlatform ?? "unknown"
            ])
        }
        AppLog.warn("Meeting", "点击 Join", [
            "platform": snap.joinPlatform ?? "unknown",
            "opened": opened,
            "meeting": String(snap.meetingID.prefix(8))
        ])

        guard opened else { return }
        let meetingID = snap.meetingID
        publish(nil, reason: "joined")
        onJoined?(meetingID)
        AppLog.info("Meeting", "入会成功，已撤回会前提示", [
            "meeting": String(meetingID.prefix(8))
        ])
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
        // 日程已结束：清提示（widget 可能已 reap，不能只靠它）。
        if current.endDate.timeIntervalSince(now) <= 0 {
            AppLog.info("Meeting", "会前提示：日程已结束，自动清除")
            publish(nil, reason: "leadTickEnded")
            return
        }
        let seconds = current.startDate.timeIntervalSince(now)
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
