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
    /// 已进入提醒窗口的会议 id：持续展示到入会或日程结束。
    private var latchedMeetingID: String?

    init(context: WidgetContext) {
        self.context = context
        calendar.start()
        MeetingLeadSession.shared.onJoin = { [weak self] in self?.joinMeeting() }
        MeetingLeadSession.shared.onRequestAuth = { [weak self] in self?.requestCalendarAccess() }
        // dropFirst：避免订阅时同步回调；初始状态靠下方同步 reevaluate。
        calendar.$nextMeeting
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
        // 进入提醒窗口后以瞬时提示挂着，直到用户点「进入」；日程结束则清场。不占内容分页。
        guard calendar.authStatus == .authorized,
              let meeting = calendar.nextMeeting
        else {
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

        if let dismissed = dismissedAfterJoinID, dismissed != meeting.id {
            dismissedAfterJoinID = nil
        }

        let lead = TimeInterval(settings.leadMinutes * 60)
        let secondsToStart = meeting.startDate.timeIntervalSince(now)
        let secondsToEnd = meeting.endDate.timeIntervalSince(now)
        let meetingAlive = secondsToEnd > 0
        let enteredLead = secondsToStart <= lead && meetingAlive

        if !meetingAlive {
            if latchedMeetingID == meeting.id {
                latchedMeetingID = nil
            }
            clearLead(reason: reason)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "ended": true,
                    "tip": false
                ])
            }
            return
        }

        if enteredLead {
            latchedMeetingID = meeting.id
        } else if latchedMeetingID != meeting.id {
            latchedMeetingID = nil
        }

        let joinedAway = dismissedAfterJoinID == meeting.id
        let shouldShow = !joinedAway && (latchedMeetingID == meeting.id)

        guard shouldShow else {
            clearLead(reason: reason)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "enteredLead": enteredLead,
                    "joinedAway": joinedAway,
                    "tip": false,
                    "secToStart": Int(secondsToStart)
                ])
            }
            return
        }

        let showJoin = meeting.join != nil
        let urgency = MeetingLeadUrgency.resolve(secondsToStart: secondsToStart)
        publishLead(
            meetingID: meeting.id,
            title: meeting.title,
            startDate: meeting.startDate,
            endDate: meeting.endDate,
            secondsToStart: secondsToStart,
            showJoin: showJoin,
            reason: reason
        )

        if reason != "tick" {
            context.log("会议展示状态", fields: [
                "reason": reason,
                "latched": true,
                "showJoin": showJoin,
                "tip": true,
                "urgency": urgency.rawValue,
                "secToStart": Int(secondsToStart)
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
                showAuth: false
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

    private func joinMeeting() {
        guard let meeting = calendar.nextMeeting else {
            AppLog.warn("Meeting", "Join 失败：无当前会议")
            return
        }
        guard let join = meeting.join else {
            AppLog.warn("Meeting", "Join 失败：无链接")
            return
        }

        var opened = NSWorkspace.shared.open(join.openURL)
        if !opened, join.openURL != join.sourceURL {
            opened = NSWorkspace.shared.open(join.sourceURL)
            AppLog.warn("Meeting", "deep link 失败，回退网页链接", [
                "platform": join.logLabel
            ])
        }
        AppLog.info("Meeting", "点击 Join", [
            "platform": join.logLabel,
            "opened": opened,
            "meeting": String(meeting.id.prefix(8))
        ])

        // 点了入会即撤提示。
        guard opened else { return }
        dismissedAfterJoinID = meeting.id
        latchedMeetingID = nil
        clearLead(reason: "joined")
        AppLog.info("Meeting", "入会成功，已撤回会前提示", [
            "meeting": String(meeting.id.prefix(8))
        ])
    }
}
