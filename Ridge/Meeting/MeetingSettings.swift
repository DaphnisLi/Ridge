import Combine
import Foundation

/// 用户自定义会议 App：名称 + 从示例链接解析出的域名。
struct CustomMeetingApp: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    /// 小写 host，如 `meet.acme.com`。
    var domain: String

    init(id: UUID = UUID(), name: String, domain: String) {
        self.id = id
        self.name = name
        self.domain = domain
    }
}

/// 会开始后何时撤掉灵动岛 tip。
enum MeetingTipDismissMode: String, CaseIterable, Identifiable, Equatable {
    /// 到达开始时间立刻撤。
    case atStart
    /// 开始后再保留若干分钟（含默认 5 与自定义）。
    case afterMinutes
    /// 一直保留到日程结束。
    case untilEnd

    var id: String { rawValue }
}

/// 会议倒计时相关用户设置。
@MainActor
final class MeetingSettings: ObservableObject {
    static let shared = MeetingSettings()

    enum Defaults {
        static let leadMinutes: Int = 10
        static let tipDismissMode: MeetingTipDismissMode = .afterMinutes
        static let tipDismissMinutes: Int = 5
        /// 空集合 = 全部内置平台启用。
        static let disabledPlatforms: Set<String> = []
    }

    private enum Key {
        static let leadMinutes = "meeting.leadMinutes"
        static let tipDismissMode = "meeting.tipDismissMode"
        static let tipDismissMinutes = "meeting.tipDismissMinutes"
        static let customApps = "meeting.customApps"
        static let disabledPlatforms = "meeting.disabledPlatforms"
    }

    static let leadMinutesRange: ClosedRange<Int> = 1...60
    /// 开始后自定义保留分钟。
    static let tipDismissMinutesRange: ClosedRange<Int> = 1...180

    /// 会前多久显示 Join。
    @Published var leadMinutes: Int {
        didSet {
            let clamped = min(max(leadMinutes, Self.leadMinutesRange.lowerBound), Self.leadMinutesRange.upperBound)
            if clamped != leadMinutes {
                leadMinutes = clamped
                return
            }
            UserDefaults.standard.set(leadMinutes, forKey: Key.leadMinutes)
        }
    }

    /// 开始后撤 tip 策略。
    @Published var tipDismissMode: MeetingTipDismissMode {
        didSet {
            UserDefaults.standard.set(tipDismissMode.rawValue, forKey: Key.tipDismissMode)
            AppLog.info("Meeting", "会后撤提示策略已更新", [
                "mode": tipDismissMode.rawValue,
                "minutes": tipDismissMinutes
            ])
        }
    }

    /// `afterMinutes` 时使用的分钟数（默认 5）。
    @Published var tipDismissMinutes: Int {
        didSet {
            let clamped = min(
                max(tipDismissMinutes, Self.tipDismissMinutesRange.lowerBound),
                Self.tipDismissMinutesRange.upperBound
            )
            if clamped != tipDismissMinutes {
                tipDismissMinutes = clamped
                return
            }
            UserDefaults.standard.set(tipDismissMinutes, forKey: Key.tipDismissMinutes)
        }
    }

    /// 用户关闭的内置平台 rawValue；未列入则视为启用。
    @Published var disabledPlatformIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledPlatformIDs), forKey: Key.disabledPlatforms)
            AppLog.debug("Meeting", "已写入平台开关", ["disabled": disabledPlatformIDs.count])
        }
    }

    /// 用户自行添加的会议 App（按域名匹配，打开用日历原链）。
    @Published var customApps: [CustomMeetingApp] {
        didSet { persistCustomApps() }
    }

    /// 是否仍应展示会前提示（已进入 lead 窗口的前提下）。
    /// - Parameters:
    ///   - secondsToStart: 距开始；已开始为负。
    ///   - secondsToEnd: 距结束。
    func shouldRetainLeadTip(secondsToStart: TimeInterval, secondsToEnd: TimeInterval) -> Bool {
        MeetingLeadTipSelector.shouldRetain(
            mode: tipDismissMode,
            minutes: tipDismissMinutes,
            secondsToStart: secondsToStart,
            secondsToEnd: secondsToEnd
        )
    }

    func isPlatformEnabled(_ platform: MeetingPlatform) -> Bool {
        guard MeetingPlatform.supportedForJoin.contains(platform) else { return true }
        return !disabledPlatformIDs.contains(platform.rawValue)
    }

    func setPlatformEnabled(_ platform: MeetingPlatform, enabled: Bool) {
        guard MeetingPlatform.supportedForJoin.contains(platform) else { return }
        if enabled {
            disabledPlatformIDs.remove(platform.rawValue)
        } else {
            disabledPlatformIDs.insert(platform.rawValue)
        }
        AppLog.info("Meeting", "平台开关变更", [
            "platform": platform.rawValue,
            "enabled": enabled
        ])
    }

    /// 检测用：当前关闭的内置平台。
    var disabledPlatforms: Set<MeetingPlatform> {
        Set(disabledPlatformIDs.compactMap(MeetingPlatform.init(rawValue:)))
    }

    /// 新增自定义会议。成功返回 nil，失败返回原因。
    @discardableResult
    func addCustomApp(name: String, sampleLink: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return L10n.Meeting.customNameRequired }
        guard let domain = MeetingLinkDetector.normalizedHost(from: sampleLink) else {
            return L10n.Meeting.customBadLink
        }
        if let existing = customApps.first(where: { $0.domain == domain }) {
            return L10n.Meeting.customDomainInUse(domain: domain, name: existing.name)
        }
        let app = CustomMeetingApp(name: trimmedName, domain: domain)
        customApps.append(app)
        AppLog.info("Meeting", "已添加自定义会议", [
            "name": trimmedName,
            "domain": domain,
            "count": customApps.count
        ])
        return nil
    }

    func removeCustomApp(id: UUID) {
        let before = customApps.count
        customApps.removeAll { $0.id == id }
        if customApps.count != before {
            AppLog.info("Meeting", "已删除自定义会议", ["count": customApps.count])
        }
    }

    /// 按 host 匹配自定义会议（精确或子域）。
    func customApp(matchingHost host: String) -> CustomMeetingApp? {
        let h = host.lowercased()
        guard !h.isEmpty else { return nil }
        return customApps.first { app in
            h == app.domain || h.hasSuffix("." + app.domain)
        }
    }

    func restoreDefaults() {
        leadMinutes = Defaults.leadMinutes
        tipDismissMode = Defaults.tipDismissMode
        tipDismissMinutes = Defaults.tipDismissMinutes
        disabledPlatformIDs = Defaults.disabledPlatforms
        AppLog.info("Meeting", "已恢复会议默认设置")
    }

    private init() {
        let defaults = UserDefaults.standard
        let rawLead = defaults.object(forKey: Key.leadMinutes)
        let lead: Int
        if let intValue = rawLead as? Int {
            lead = intValue
        } else if let doubleValue = rawLead as? Double {
            lead = Int(doubleValue.rounded())
        } else {
            lead = Defaults.leadMinutes
        }
        leadMinutes = min(max(lead, Self.leadMinutesRange.lowerBound), Self.leadMinutesRange.upperBound)

        if let rawMode = defaults.string(forKey: Key.tipDismissMode),
           let mode = MeetingTipDismissMode(rawValue: rawMode)
        {
            tipDismissMode = mode
        } else {
            tipDismissMode = Defaults.tipDismissMode
        }

        let rawGrace = defaults.object(forKey: Key.tipDismissMinutes) as? Int
            ?? Defaults.tipDismissMinutes
        tipDismissMinutes = min(
            max(rawGrace, Self.tipDismissMinutesRange.lowerBound),
            Self.tipDismissMinutesRange.upperBound
        )

        if let data = defaults.data(forKey: Key.customApps),
           let decoded = try? JSONDecoder().decode([CustomMeetingApp].self, from: data) {
            customApps = decoded
        } else {
            customApps = []
        }

        let known = Set(MeetingPlatform.supportedForJoin.map(\.rawValue))
        disabledPlatformIDs = Set(defaults.stringArray(forKey: Key.disabledPlatforms) ?? [])
            .intersection(known)

        AppLog.debug("Meeting", "已加载会议设置", [
            "leadMinutes": leadMinutes,
            "tipDismissMode": tipDismissMode.rawValue,
            "tipDismissMinutes": tipDismissMinutes,
            "customApps": customApps.count,
            "disabledPlatforms": disabledPlatformIDs.count
        ])
    }

    private func persistCustomApps() {
        if let data = try? JSONEncoder().encode(customApps) {
            UserDefaults.standard.set(data, forKey: Key.customApps)
            AppLog.debug("Meeting", "已写入自定义会议", ["count": customApps.count])
        } else {
            AppLog.warn("Meeting", "自定义会议写入失败")
        }
    }
}
