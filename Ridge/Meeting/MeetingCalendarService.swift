import AppKit
import Combine
import EventKit
import Foundation

struct MeetingEvent: Equatable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarIdentifier: String
    let calendarTitle: String
    let join: MeetingJoinTarget?

    var isAllDay: Bool = false
}

enum MeetingAuthStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// EventKit 读取未来会议，并推送变更。
@MainActor
final class MeetingCalendarService: ObservableObject {
    static let shared = MeetingCalendarService()

    @Published private(set) var authStatus: MeetingAuthStatus = .notDetermined
    /// 未结束的近期会议（按开始时间升序）；会前提示可在第一场关掉后切到下一场。
    @Published private(set) var upcomingMeetings: [MeetingEvent] = []
    /// 最近一场未结束会议（兼容旧调用）。
    var nextMeeting: MeetingEvent? { upcomingMeetings.first }
    @Published private(set) var lastErrorMessage: String?

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private let settings = MeetingSettings.shared
    private var settingsObservers: Set<AnyCancellable> = []

    private init() {
        refreshAuthStatus()
        settings.$leadMinutes
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshUpcoming(reason: "settings")
            }
            .store(in: &settingsObservers)
        settings.$customApps
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshUpcoming(reason: "customApps")
            }
            .store(in: &settingsObservers)
    }

    func start() {
        refreshAuthStatus()
        if authStatus == .authorized {
            beginObserving()
            refreshUpcoming(reason: "start")
        }
        AppLog.info("Meeting", "日历服务已启动", ["auth": "\(authStatus)"])
    }

    func stop() {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
        AppLog.info("Meeting", "日历服务已停止")
    }

    func refreshAuthStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authStatus = mapAuth(status)
    }

    /// 请求日历完全访问权限（macOS 14+）。
    func requestAccess() async -> Bool {
        refreshAuthStatus()
        AppLog.info("Meeting", "开始请求日历权限", ["status": "\(authStatus)"])

        if authStatus == .authorized {
            beginObserving()
            refreshUpcoming(reason: "alreadyAuthorized")
            return true
        }

        // 已拒绝 / 受限：系统不会再弹窗，直接带去隐私设置。
        if authStatus == .denied || authStatus == .restricted {
            AppLog.warn("Meeting", "日历权限已拒绝，打开系统设置")
            openSystemPrivacySettings()
            return false
        }

        // 确保权限对话框能到前台（设置窗打开时尤其需要）。
        NSApp.activate(ignoringOtherApps: true)

        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            refreshAuthStatus()
            AppLog.info("Meeting", "日历授权结果", [
                "granted": granted,
                "status": "\(authStatus)"
            ])
            if granted {
                beginObserving()
                refreshUpcoming(reason: "authorized")
            } else if authStatus == .denied || authStatus == .restricted {
                lastErrorMessage = L10n.Meeting.calendarDeniedShort
                openSystemPrivacySettings()
            }
            return granted
        } catch {
            lastErrorMessage = L10n.Meeting.calendarRequestFailed
            AppLog.error("Meeting", "日历授权失败", ["error": error.localizedDescription])
            refreshAuthStatus()
            return false
        }
    }

    func openSystemPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                AppLog.info("Meeting", "已打开系统日历隐私设置", ["url": raw])
                return
            }
        }
        AppLog.warn("Meeting", "无法打开系统日历隐私设置")
    }

    func refreshUpcoming(reason: String) {
        refreshAuthStatus()
        guard authStatus == .authorized else {
            upcomingMeetings = []
            AppLog.debug("Meeting", "未授权，跳过刷新", ["reason": reason])
            return
        }

        // 直接遍历系统全部日历；从 location / notes / url 解析入会链接。
        let ekCalendars = store.calendars(for: .event)
        guard !ekCalendars.isEmpty else {
            upcomingMeetings = []
            AppLog.debug("Meeting", "系统无日历源", ["reason": reason])
            return
        }

        let now = Date()
        let windowEnd = now.addingTimeInterval(60 * 60 * 24)
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60 * 30),
            end: windowEnd,
            calendars: ekCalendars
        )
        // 全部未结束非全天事件（按开始时间）；提示层再按 lead / 保留策略挑场。
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        let customs = settings.customApps
        let mapped: [MeetingEvent] = events.map { ek in
            let join = MeetingLinkDetector.detect(
                location: ek.location,
                notes: ek.notes,
                url: ek.url,
                customApps: customs
            )
            return MeetingEvent(
                id: ek.eventIdentifier ?? "\(ek.startDate.timeIntervalSince1970)-\(ek.title ?? "")",
                title: (ek.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.Meeting.untitled,
                startDate: ek.startDate,
                endDate: ek.endDate,
                calendarIdentifier: ek.calendar.calendarIdentifier,
                calendarTitle: ek.calendar.title,
                join: join,
                isAllDay: ek.isAllDay
            )
        }

        // 有入会链接的优先排在同起点之前：同 start 时带 join 的排前；整体仍按 start 升序。
        let ordered = mapped.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            switch (lhs.join != nil, rhs.join != nil) {
            case (true, false): return true
            case (false, true): return false
            default: return false
            }
        }

        upcomingMeetings = ordered
        if let first = ordered.first {
            AppLog.info("Meeting", "已刷新近期会议", [
                "reason": reason,
                "count": ordered.count,
                "titlePrefix": String(first.title.prefix(8)),
                "startInSec": Int(first.startDate.timeIntervalSinceNow),
                "hasJoin": first.join != nil,
                "platform": first.join?.logLabel ?? "none"
            ])
        } else {
            AppLog.debug("Meeting", "窗口内无会议", ["reason": reason])
        }
    }

    private func beginObserving() {
        if changeObserver == nil {
            changeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: store,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshUpcoming(reason: "storeChanged")
                }
            }
        }
        refreshTimer?.invalidate()
        // 轻量兜底：每 60s 扫一次，避免漏通知。
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUpcoming(reason: "timer")
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func mapAuth(_ status: EKAuthorizationStatus) -> MeetingAuthStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .authorized
        case .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
