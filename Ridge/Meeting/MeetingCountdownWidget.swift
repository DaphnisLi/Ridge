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
    private var model = MeetingCountdownModel()
    /// 用户已点击入会的会议 id；该场会不再上岛，直到换下一场。
    private var dismissedAfterJoinID: String?
    /// 已进入提醒窗口的会议 id：持续展示到入会或日程结束。
    private var latchedMeetingID: String?
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    init(context: WidgetContext) {
        self.context = context
        calendar.start()
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
        // 同步评估：只置 wantsDisplay，供 ensureInstance 在 make 返回后写入 demand，避免同轮 recompute 被 reap 掉。
        // requestDisplay 仍延后，避免 init 未完成时重入创建。
        reevaluate(reason: "init")
    }

    func makeView() -> AnyView {
        AnyView(
            MeetingCountdownLiveView(
                model: model,
                onJoin: { [weak self] in self?.joinMeeting() },
                onRequestAuth: { [weak self] in self?.requestCalendarAccess() }
            )
        )
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
        // 进入提醒窗口后常驻展示，直到用户点「进入会议」；日程结束则清场。
        guard calendar.authStatus == .authorized,
              let meeting = calendar.nextMeeting
        else {
            latchedMeetingID = nil
            updateDemand(shouldShow: false, reason: reason)
            model.applyEmpty(auth: calendar.authStatus)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "empty": true,
                    "auth": "\(calendar.authStatus)",
                    "onIsland": false
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
            updateDemand(shouldShow: false, reason: reason)
            model.applyEmpty(auth: .authorized)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "ended": true,
                    "onIsland": false
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
        updateDemand(shouldShow: shouldShow, reason: reason)

        guard shouldShow else {
            model.applyEmpty(auth: .authorized)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "enteredLead": enteredLead,
                    "joinedAway": joinedAway,
                    "onIsland": false,
                    "secToStart": Int(secondsToStart)
                ])
            }
            return
        }

        let showJoin = meeting.join != nil
        let statusText: String
        if secondsToStart > 0 {
            let minutes = max(1, Int(ceil(secondsToStart / 60)))
            statusText = L10n.Meeting.previewMinutesAhead(minutes)
        } else {
            statusText = L10n.Meeting.inProgress
        }
        let range = "\(timeFormatter.string(from: meeting.startDate)) - \(timeFormatter.string(from: meeting.endDate))"

        model.apply(
            title: meeting.title,
            platformBadge: meeting.join?.displayName,
            statusText: statusText,
            timeRangeText: range,
            showJoin: showJoin
        )

        if reason != "tick" {
            context.log("会议展示状态", fields: [
                "reason": reason,
                "latched": true,
                "showJoin": showJoin,
                "onIsland": true,
                "secToStart": Int(secondsToStart)
            ])
        }
    }

    private func updateDemand(shouldShow: Bool, reason: String) {
        if shouldShow {
            if !wantsDisplay {
                wantsDisplay = true
                requestedAt = Date()
                AppLog.info("Meeting", "申请展示（会前窗口）", ["reason": reason])
                // 延后到 Runtime 已登记本实例后再 request，避免 init 重入；wantsDisplay 已同步置位防 reap。
                Task { @MainActor [weak self] in
                    guard let self, self.wantsDisplay else { return }
                    self.context.requestDisplay()
                    AppLog.debug("Meeting", "已提交 requestDisplay", ["reason": reason])
                }
            }
        } else if wantsDisplay {
            wantsDisplay = false
            context.withdrawDisplay()
            AppLog.info("Meeting", "撤回展示", ["reason": reason])
        }
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

        // 点了入会即撤岛：提醒窗口起一直展示，到此结束。
        guard opened else { return }
        dismissedAfterJoinID = meeting.id
        latchedMeetingID = nil
        updateDemand(shouldShow: false, reason: "joined")
        AppLog.info("Meeting", "入会成功，已撤回岛展示", [
            "meeting": String(meeting.id.prefix(8))
        ])
    }

}

// MARK: - View model

@MainActor
final class MeetingCountdownModel: ObservableObject {
    @Published var title: String = L10n.Meeting.widgetName
    @Published var platformBadge: String?
    @Published var statusText: String = L10n.Meeting.noUpcoming
    @Published var timeRangeText: String?
    @Published var showJoin = false
    @Published var needsAuth = false

    func applyEmpty(auth: MeetingAuthStatus) {
        platformBadge = nil
        timeRangeText = nil
        showJoin = false
        switch auth {
        case .authorized:
            needsAuth = false
            title = L10n.Meeting.widgetName
            statusText = L10n.Meeting.noUpcoming
        case .notDetermined:
            needsAuth = true
            title = L10n.Meeting.countdownTitle
            statusText = L10n.Meeting.calendarNeedAuth
        case .denied, .restricted:
            needsAuth = true
            title = L10n.Meeting.countdownTitle
            statusText = L10n.Meeting.calendarDeniedShort
        }
    }

    func apply(
        title: String,
        platformBadge: String?,
        statusText: String,
        timeRangeText: String?,
        showJoin: Bool
    ) {
        needsAuth = false
        self.title = title
        self.platformBadge = platformBadge
        self.statusText = statusText
        self.timeRangeText = timeRangeText
        self.showJoin = showJoin
    }
}

private struct MeetingCountdownLiveView: View {
    @ObservedObject var model: MeetingCountdownModel
    let onJoin: () -> Void
    let onRequestAuth: () -> Void

    var body: some View {
        MeetingIslandCardView(
            title: model.title,
            platformBadge: model.platformBadge,
            statusText: model.statusText,
            timeRangeText: model.timeRangeText,
            showJoin: model.showJoin,
            showAuth: model.needsAuth,
            onJoin: onJoin,
            onRequestAuth: onRequestAuth
        )
    }
}
