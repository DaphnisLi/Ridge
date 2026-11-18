#if DEBUG
import EventKit
import Foundation

/// 往系统日历写入真实测试会议；标题前缀 `[Ridge Lab]`，可一键清理。
enum IslandTestLabMeetingSeeder {
    static let titlePrefix = "[Ridge Lab]"

    private enum Key {
        static let eventIDs = "debug.islandTestLab.meetingEventIDs"
    }

    /// 紧迫度 → 距开始秒数（对齐 `MeetingLeadUrgency`）。
    nonisolated static func secondsUntilStart(for urgency: MeetingLeadUrgency) -> TimeInterval {
        switch urgency {
        case .relaxed: return 10 * 60
        case .warning: return 5 * 60
        case .critical: return 90
        }
    }

    nonisolated static func sampleJoinURL(for platform: MeetingPlatform) -> URL {
        switch platform {
        case .zoom:
            return URL(string: "https://zoom.us/j/12345678901")!
        case .googleMeet:
            return URL(string: "https://meet.google.com/abc-defg-hij")!
        case .teams:
            return URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_RidgeLabTest")!
        case .webex:
            return URL(string: "https://example.webex.com/meet/ridge-lab")!
        case .faceTime:
            return URL(string: "facetime://lab@example.com")!
        case .tencentMeeting:
            return URL(string: "https://meeting.tencent.com/dm/RidgeLabTest")!
        case .lark:
            return URL(string: "https://vc.feishu.cn/j/123456789")!
        case .dingTalk:
            return URL(string: "https://meeting.dingtalk.com/j/RidgeLabTest")!
        case .custom, .generic:
            return URL(string: "https://example.com/meeting/ridge-lab")!
        }
    }

    /// 创建一场真实事件；成功返回 eventIdentifier。
    @MainActor
    @discardableResult
    static func createMeeting(
        platform: MeetingPlatform,
        urgency: MeetingLeadUrgency
    ) throws -> String {
        let store = EKEventStore()
        let auth = MeetingCalendarService.shared.authStatus
        guard auth == .authorized else {
            AppLog.warn("TestLab", "创建会议失败：日历未授权", ["auth": "\(auth)"])
            throw LabError.calendarNotAuthorized
        }
        guard let calendar = store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications })
        else {
            throw LabError.noWritableCalendar
        }

        let start = Date().addingTimeInterval(secondsUntilStart(for: urgency))
        let end = start.addingTimeInterval(30 * 60)
        let joinURL = sampleJoinURL(for: platform)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "\(titlePrefix) \(platform.displayName) · \(urgency.stageTitle)"
        event.startDate = start
        event.endDate = end
        event.notes = "Ridge 岛测试台写入\n\(joinURL.absoluteString)"
        event.location = joinURL.absoluteString
        event.url = joinURL

        try store.save(event, span: .thisEvent, commit: true)
        let id = event.eventIdentifier ?? ""
        if !id.isEmpty {
            remember(eventID: id)
        }
        MeetingCalendarService.shared.refreshUpcoming(reason: "testLabCreate")
        AppLog.info("TestLab", "已写入测试会议", [
            "platform": platform.rawValue,
            "urgency": urgency.rawValue,
            "startInSec": Int(start.timeIntervalSinceNow),
            "idPrefix": String(id.prefix(8))
        ])
        return id
    }

    /// 删除本工具记住的测试事件，并扫标题前缀兜底。
    @MainActor
    static func cleanupAll() throws -> Int {
        let store = EKEventStore()
        guard MeetingCalendarService.shared.authStatus == .authorized else {
            throw LabError.calendarNotAuthorized
        }
        var ids = Set(storedEventIDs())
        let windowStart = Date().addingTimeInterval(-2 * 60 * 60)
        let windowEnd = Date().addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: nil
        )
        for event in store.events(matching: predicate) {
            let title = event.title ?? ""
            if title.hasPrefix(titlePrefix), let eid = event.eventIdentifier {
                ids.insert(eid)
            }
        }

        var deleted = 0
        for id in ids {
            guard let event = store.event(withIdentifier: id) else { continue }
            do {
                try store.remove(event, span: .thisEvent, commit: false)
                deleted += 1
            } catch {
                AppLog.warn("TestLab", "删除测试会议失败", [
                    "idPrefix": String(id.prefix(8)),
                    "error": error.localizedDescription
                ])
            }
        }
        if deleted > 0 {
            try store.commit()
        }
        UserDefaults.standard.removeObject(forKey: Key.eventIDs)
        MeetingCalendarService.shared.refreshUpcoming(reason: "testLabCleanup")
        AppLog.info("TestLab", "已清理测试会议", ["deleted": deleted])
        return deleted
    }

    enum LabError: LocalizedError {
        case calendarNotAuthorized
        case noWritableCalendar

        var errorDescription: String? {
            switch self {
            case .calendarNotAuthorized:
                return L10n.TestLab.meetingNeedAuth
            case .noWritableCalendar:
                return L10n.TestLab.meetingNoCalendar
            }
        }
    }

    private static func storedEventIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: Key.eventIDs) ?? []
    }

    private static func remember(eventID: String) {
        var ids = storedEventIDs()
        if !ids.contains(eventID) {
            ids.append(eventID)
            UserDefaults.standard.set(ids, forKey: Key.eventIDs)
        }
    }
}
#endif
