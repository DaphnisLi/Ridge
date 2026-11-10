import AppKit
import Combine
import Foundation
import SwiftUI

/// 会前倒计时 + 一键入会（EventKit）。
@MainActor
final class MeetingCountdownWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.meeting",
        displayName: L10n.Meeting.widgetName,
        summary: L10n.Meeting.widgetSummary,
        source: .builtin,
        kind: .content,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let calendar = MeetingCalendarService.shared
    private let settings = MeetingSettings.shared

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    /// 会议卡自带标题行，岛顶栏不再重复。
    var title: String { "" }

    private var tick: Timer?
    private var observers: Set<AnyCancellable> = []
    /// 用户已点击入会的会议 id；该场会不再上岛，直到换下一场。
    private var dismissedAfterJoinID: String?
    /// 已进入提醒窗口的会议 id：持续展示到入会或保留窗口结束。
    private var latchedMeetingID: String?

    init(context: WidgetContext) {
        self.context = context
        calendar.start()
        // 入会打开链接由 MeetingLeadSession 自持；此处只记「已入会」以免同场会再上岛。
        MeetingLeadSession.shared.onJoined = { [weak self] meetingID in
            self?.dismissedAfterJoinID = meetingID
            self?.latchedMeetingID = nil
            AppLog.info("Meeting", "会话入会回调：已标记 dismissed", [
                "meeting": String(meetingID.prefix(8))
            ])
            // 入会撤掉本场后，立刻看是否该提示下一场。
            self?.reevaluate(reason: "joinedAdvance")
        }
        MeetingLeadSession.shared.onTipExpired = { [weak self] reason in
            // 开始后保留窗口结束：清 latch，改选下一场。
            self?.latchedMeetingID = nil
            self?.reevaluate(reason: reason)
        }
        MeetingLeadSession.shared.onRequestAuth = { [weak self] in self?.requestCalendarAccess() }
        // dropFirst：避免订阅时同步回调；初始状态靠下方同步 reevaluate。
        calendar.$upcomingMeetings
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reevaluate(reason: "meetingChanged")
            }
            .store(in: &observers)
        settings.$leadMinutes
            .dropFirst()
            .sink { [weak self] _ in
                self?.reevaluate(reason: "meetingSettings")
            }
            .store(in: &observers)
        settings.$tipDismissMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.reevaluate(reason: "tipDismissSettings")
            }
            .store(in: &observers)
        settings.$tipDismissMinutes
            .dropFirst()
            .sink { [weak self] _ in
                self?.reevaluate(reason: "tipDismissSettings")
            }
            .store(in: &observers)
        startTicking()
        // 提示类：只写 MeetingLeadSession → IslandNotice，不 requestDisplay 占分页。
        reevaluate(reason: "init")
    }

    func makeView() -> AnyView {
        // 设置预览仍用假数据卡；真机岛上走瞬时通知，不占内容页。
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("会议倒计时 onAppear")
        calendar.start()
        startTicking()
        reevaluate(reason: "appear")
    }

    func onDisappear() {
        context.log("会议倒计时 onDisappear")
        stopTicking()
    }

    func refresh() {
        calendar.refreshUpcoming(reason: "widgetRefresh")
        reevaluate(reason: "refresh")
    }

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reevaluate(reason: "tick")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }

    private func reevaluate(reason: String) {
        let now = Date()
        guard calendar.authStatus == .authorized else {
            latchedMeetingID = nil
            clearLead(reason: reason)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "empty": true,
                    "auth": "\(calendar.authStatus)",
                    "tip": false
                ])
            }
            return
        }

        let meetings = calendar.upcomingMeetings
        // 已入会场次若不在列表（已结束），清 dismissed，避免脏状态挡下一场。
        if let dismissed = dismissedAfterJoinID,
           !meetings.contains(where: { $0.id == dismissed })
        {
            dismissedAfterJoinID = nil
        }

        let input = MeetingLeadTipSelector.Input(
            now: now,
            leadSeconds: TimeInterval(settings.leadMinutes * 60),
            tipDismissMode: settings.tipDismissMode,
            tipDismissMinutes: settings.tipDismissMinutes,
            dismissedAfterJoinID: dismissedAfterJoinID,
            latchedMeetingID: latchedMeetingID
        )

        guard let selected = MeetingLeadTipSelector.select(from: meetings, input: input) else {
            if latchedMeetingID != nil {
                AppLog.info("Meeting", "会前提示窗口已结束，暂无下一场可提示", [
                    "reason": reason,
                    "upcoming": meetings.count,
                    "previousLatch": String((latchedMeetingID ?? "").prefix(8))
                ])
            }
            latchedMeetingID = nil
            clearLead(reason: reason)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "upcoming": meetings.count,
                    "tip": false
                ])
            }
            return
        }

        let meeting = selected.meeting
        let previousLatch = latchedMeetingID
        if selected.shouldLatch {
            latchedMeetingID = meeting.id
        }

        if previousLatch != nil, previousLatch != meeting.id {
            AppLog.info("Meeting", "会前提示已切换到下一场", [
                "reason": reason,
                "from": String((previousLatch ?? "").prefix(8)),
                "to": String(meeting.id.prefix(8)),
                "secToStart": Int(meeting.startDate.timeIntervalSince(now))
            ])
        }

        let secondsToStart = meeting.startDate.timeIntervalSince(now)
        let join = meeting.join
        let showJoin = join != nil
        let urgency = MeetingLeadUrgency.resolve(secondsToStart: secondsToStart)
        publishLead(
            meetingID: meeting.id,
            title: meeting.title,
            startDate: meeting.startDate,
            endDate: meeting.endDate,
            secondsToStart: secondsToStart,
            showJoin: showJoin,
            joinOpenURL: join?.openURL,
            joinSourceURL: join?.sourceURL,
            joinPlatform: join?.logLabel,
            reason: reason
        )

        if reason != "tick" {
            context.log("会议展示状态", fields: [
                "reason": reason,
                "latched": true,
                "showJoin": showJoin,
                "tip": true,
                "urgency": urgency.rawValue,
                "secToStart": Int(secondsToStart),
                "upcoming": meetings.count
            ])
        }
    }

    private func publishLead(
        meetingID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        secondsToStart: TimeInterval,
        showJoin: Bool,
        joinOpenURL: URL?,
        joinSourceURL: URL?,
        joinPlatform: String?,
        reason: String
    ) {
        wantsDisplay = false
        MeetingLeadSession.shared.publish(
            .init(
                meetingID: meetingID,
                title: title,
                startDate: startDate,
                endDate: endDate,
                secondsToStart: secondsToStart,
                showJoin: showJoin,
                showAuth: false,
                joinOpenURL: joinOpenURL,
                joinSourceURL: joinSourceURL,
                joinPlatform: joinPlatform
            ),
            reason: reason
        )
    }

    private func clearLead(reason: String) {
        wantsDisplay = false
        MeetingLeadSession.shared.publish(nil, reason: reason)
    }

    private func requestCalendarAccess() {
        AppLog.info("Meeting", "岛上点击授权")
        Task {
            let granted = await calendar.requestAccess()
            reevaluate(reason: "authResult")
            if !granted, calendar.authStatus == .denied || calendar.authStatus == .restricted {
                // 系统不再弹窗时，打开设置页方便用户对照说明。
                SettingsNavigator.shared.openWidgetPreview(Self.manifest.id)
            }
        }
    }

}
