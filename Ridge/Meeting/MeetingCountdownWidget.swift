import AppKit
import Combine
import Foundation
import SwiftUI

/// 会前倒计时 + 一键入会（EventKit）。
@MainActor
final class MeetingCountdownWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.meeting",
        displayName: "下一场会议",
        summary: "下一场会议倒计时，到点一键入会",
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

    private var tick: Timer?
    private var observers: Set<AnyCancellable> = []
    private var model = MeetingCountdownModel()

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
        AnyView(MeetingCountdownView(model: model, onJoin: { [weak self] in
            self?.joinMeeting()
        }, onRequestAuth: { [weak self] in
            self?.requestCalendarAccess()
        }))
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
        // 开关打开即上岛：空态 / 未授权也展示；提前分钟只控制 Join，不撤回展示。
        updateDemand(shouldShow: true, reason: reason)

        let now = Date()
        guard calendar.authStatus == .authorized,
              let meeting = calendar.nextMeeting
        else {
            model.applyEmpty(auth: calendar.authStatus)
            if reason != "tick" {
                context.log("会议展示状态", fields: [
                    "reason": reason,
                    "empty": true,
                    "auth": "\(calendar.authStatus)"
                ])
            }
            return
        }

        let lead = TimeInterval(settings.leadMinutes * 60)
        let secondsToStart = meeting.startDate.timeIntervalSince(now)
        let secondsToEnd = meeting.endDate.timeIntervalSince(now)
        let inWindow = secondsToStart <= lead && secondsToEnd > 0
        let showJoin = inWindow && meeting.join != nil

        let countdownText: String
        if secondsToStart > 0 {
            countdownText = Self.formatCountdown(secondsToStart)
        } else if secondsToEnd > 0 {
            countdownText = "进行中"
        } else {
            countdownText = "已结束"
        }

        model.apply(
            title: meeting.title,
            subtitle: countdownText,
            platformName: meeting.join?.displayName,
            showJoin: showJoin
        )

        if reason != "tick" {
            context.log("会议展示状态", fields: [
                "reason": reason,
                "inWindow": inWindow,
                "showJoin": showJoin,
                "secToStart": Int(secondsToStart)
            ])
        }
    }

    private func updateDemand(shouldShow: Bool, reason: String) {
        if shouldShow {
            if !wantsDisplay {
                wantsDisplay = true
                requestedAt = Date()
                AppLog.info("Meeting", "申请展示（与开关同步）", ["reason": reason])
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
        guard let join = calendar.nextMeeting?.join else {
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
            "opened": opened
        ])
    }

    private static func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - View model

@MainActor
final class MeetingCountdownModel: ObservableObject {
    @Published var title: String = "下一场会议"
    @Published var subtitle: String = "暂无即将开始的日程"
    @Published var platformName: String?
    @Published var showJoin = false
    @Published var needsAuth = false

    func applyEmpty(auth: MeetingAuthStatus) {
        platformName = nil
        showJoin = false
        switch auth {
        case .authorized:
            needsAuth = false
            title = "下一场会议"
            subtitle = "暂无即将开始的日程"
        case .notDetermined:
            needsAuth = true
            title = "会议倒计时"
            subtitle = "需要日历权限"
        case .denied, .restricted:
            needsAuth = true
            title = "会议倒计时"
            subtitle = "未授予日历权限"
        }
    }

    func apply(title: String, subtitle: String, platformName: String?, showJoin: Bool) {
        needsAuth = false
        self.title = title
        self.subtitle = subtitle
        self.platformName = platformName
        self.showJoin = showJoin
    }
}

// MARK: - UI

private struct MeetingCountdownView: View {
    @ObservedObject var model: MeetingCountdownModel
    let onJoin: () -> Void
    let onRequestAuth: () -> Void
    @Environment(\.islandPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.icon)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.subtitle)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.secondary)
                    if let platformName = model.platformName, !model.needsAuth {
                        Text("· \(platformName)")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if model.needsAuth {
                Button(action: onRequestAuth) {
                    Text("授权")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accentForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(palette.accentFill))
                }
                .buttonStyle(.plain)
            } else if model.showJoin {
                Button(action: onJoin) {
                    Text("Join")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.accentForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(palette.accentFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("加入会议")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
