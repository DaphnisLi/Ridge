import AppKit
import Foundation

/// 会议平台（含海外 + 国内）。
enum MeetingPlatform: String, CaseIterable, Identifiable, Hashable {
    case zoom
    case googleMeet
    case teams
    case webex
    case faceTime
    case tencentMeeting
    case lark
    case dingTalk
    case custom
    case generic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .googleMeet: return "Google Meet"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .faceTime: return "FaceTime"
        case .tencentMeeting: return "腾讯会议"
        case .lark: return "飞书会议"
        case .dingTalk: return "钉钉会议"
        case .custom: return "自定义"
        case .generic: return "浏览器"
        }
    }

    /// 用于检测本机是否安装对应 App。
    var bundleIdentifiers: [String] {
        switch self {
        case .zoom: return ["us.zoom.xos"]
        case .googleMeet: return ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari"]
        case .teams: return ["com.microsoft.teams", "com.microsoft.teams2"]
        case .webex: return ["com.cisco.webexmeetingsapp", "Cisco-Systems.Spark"]
        case .faceTime: return ["com.apple.FaceTime"]
        case .tencentMeeting: return ["com.tencent.meeting"]
        case .lark: return ["com.electron.lark", "com.bytedance.macos.feishu"]
        case .dingTalk: return ["com.alibaba.DingTalkMac"]
        case .custom, .generic: return []
        }
    }

    var isInstalled: Bool {
        if self == .generic || self == .custom || self == .googleMeet { return true }
        return bundleIdentifiers.contains {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    /// 设置页展示用：可识别域名并尝试一键入会的平台（不含泛型网页）。
    static var supportedForJoin: [MeetingPlatform] {
        [.zoom, .googleMeet, .teams, .webex, .faceTime, .tencentMeeting, .lark, .dingTalk]
    }
}

struct MeetingJoinTarget: Equatable {
    let platform: MeetingPlatform
    /// 优先用于 `NSWorkspace.open` 的 URL（可能是 deep link）。
    let openURL: URL
    /// 原始网页链接（日志 / 回退）。
    let sourceURL: URL
    /// 自定义会议显示名；内置平台为 nil。
    let customName: String?

    init(
        platform: MeetingPlatform,
        openURL: URL,
        sourceURL: URL,
        customName: String? = nil
    ) {
        self.platform = platform
        self.openURL = openURL
        self.sourceURL = sourceURL
        self.customName = customName
    }

    var displayName: String {
        customName ?? platform.displayName
    }

    var logLabel: String {
        if let customName, !customName.isEmpty {
            return "custom:\(customName)"
        }
        return platform.rawValue
    }
}

/// 从日历事件的 location / notes / url 中识别会议链接并映射 deep link。
enum MeetingLinkDetector {
    private static let urlRegex: NSRegularExpression = {
        // 粗匹配 http(s) / 自定义 scheme。
        let pattern = #"(?i)\b((?:https?|zoommtg|msteams|wemeet|lark|dingtalk|facetime|webexmeetings):[^\s<>\"']+)"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func detect(
        location: String?,
        notes: String?,
        url: URL?,
        customApps: [CustomMeetingApp] = [],
        disabledPlatforms: Set<MeetingPlatform> = []
    ) -> MeetingJoinTarget? {
        var candidates: [URL] = []
        if let url { candidates.append(url) }
        candidates.append(contentsOf: extractURLs(from: location))
        candidates.append(contentsOf: extractURLs(from: notes))

        for candidate in candidates {
            if let target = map(
                candidate,
                customApps: customApps,
                disabledPlatforms: disabledPlatforms
            ) {
                return target
            }
        }
        return nil
    }

    static func extractURLs(from text: String?) -> [URL] {
        guard let text, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return urlRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            var raw = String(text[swiftRange])
            // 去掉尾部常见标点。
            while let last = raw.last, ".,);]》」』".contains(last) {
                raw.removeLast()
            }
            return URL(string: raw)
        }
    }

    static func map(
        _ url: URL,
        customApps: [CustomMeetingApp] = [],
        disabledPlatforms: Set<MeetingPlatform> = []
    ) -> MeetingJoinTarget? {
        let absolute = url.absoluteString
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()

        func accept(_ target: MeetingJoinTarget) -> MeetingJoinTarget? {
            if disabledPlatforms.contains(target.platform) { return nil }
            return target
        }

        // 已是 deep link
        if scheme == "zoommtg" {
            return accept(MeetingJoinTarget(platform: .zoom, openURL: url, sourceURL: url))
        }
        if scheme == "msteams" {
            return accept(MeetingJoinTarget(platform: .teams, openURL: url, sourceURL: url))
        }
        if scheme == "wemeet" {
            return accept(MeetingJoinTarget(platform: .tencentMeeting, openURL: url, sourceURL: url))
        }
        if scheme == "lark" || scheme == "feishu" {
            return accept(MeetingJoinTarget(platform: .lark, openURL: url, sourceURL: url))
        }
        if scheme == "dingtalk" {
            return accept(MeetingJoinTarget(platform: .dingTalk, openURL: url, sourceURL: url))
        }
        if scheme == "facetime" || scheme == "facetime-audio" {
            return accept(MeetingJoinTarget(platform: .faceTime, openURL: url, sourceURL: url))
        }
        if scheme == "webexmeetings" {
            return accept(MeetingJoinTarget(platform: .webex, openURL: url, sourceURL: url))
        }

        // Zoom https://zoom.us/j/123 或 zoom.com
        if host.contains("zoom.us") || host.contains("zoom.com") {
            if let deep = zoomDeepLink(from: url) {
                return accept(MeetingJoinTarget(platform: .zoom, openURL: deep, sourceURL: url))
            }
            return accept(MeetingJoinTarget(platform: .zoom, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // Google Meet
        if host.contains("meet.google.com") {
            return accept(MeetingJoinTarget(platform: .googleMeet, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // Teams
        if host.contains("teams.microsoft.com")
            || host.contains("teams.live.com")
            || absolute.lowercased().contains("meetup-join") {
            if let deep = teamsDeepLink(from: url) {
                return accept(MeetingJoinTarget(platform: .teams, openURL: deep, sourceURL: url))
                    ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
            }
            return accept(MeetingJoinTarget(platform: .teams, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // Webex
        if host.contains("webex.com") {
            return accept(MeetingJoinTarget(platform: .webex, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // FaceTime
        if host.contains("facetime.apple.com") {
            return accept(MeetingJoinTarget(platform: .faceTime, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // 腾讯会议
        if host.contains("meeting.tencent.com")
            || host.contains("voovmeeting.com")
            || host.contains("tencentmeeting.com") {
            if let deep = tencentDeepLink(from: url) {
                return accept(MeetingJoinTarget(platform: .tencentMeeting, openURL: deep, sourceURL: url))
                    ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
            }
            return accept(MeetingJoinTarget(platform: .tencentMeeting, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // 飞书 / Lark
        if host.contains("vc.larksuite.com")
            || host.contains("vc.feishu.cn")
            || host.contains("vc.larkoffice.com")
            || host.contains("meeting.feishu.cn") {
            if let deep = larkDeepLink(from: url) {
                return accept(MeetingJoinTarget(platform: .lark, openURL: deep, sourceURL: url))
                    ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
            }
            return accept(MeetingJoinTarget(platform: .lark, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // 钉钉
        if host.contains("meeting.dingtalk.com") || host.contains("dingtalk.com") && absolute.contains("meeting") {
            if let deep = dingTalkDeepLink(from: url) {
                return accept(MeetingJoinTarget(platform: .dingTalk, openURL: deep, sourceURL: url))
                    ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
            }
            return accept(MeetingJoinTarget(platform: .dingTalk, openURL: url, sourceURL: url))
                ?? MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        // 用户自定义：按域名匹配，打开用日历原链。
        if let custom = matchCustomApp(host: host, in: customApps) {
            return MeetingJoinTarget(
                platform: .custom,
                openURL: url,
                sourceURL: url,
                customName: custom.name
            )
        }

        if scheme == "http" || scheme == "https" {
            return MeetingJoinTarget(platform: .generic, openURL: url, sourceURL: url)
        }

        _ = absolute
        return nil
    }

    /// 从用户粘贴的示例链接解析规范化 host（去 www.）。
    static func normalizedHost(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let url = URL(string: candidate),
              var host = url.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    private static func matchCustomApp(host: String, in apps: [CustomMeetingApp]) -> CustomMeetingApp? {
        let h = host.lowercased()
        guard !h.isEmpty else { return nil }
        return apps.first { app in
            h == app.domain || h.hasSuffix("." + app.domain)
        }
    }

    // MARK: - Deep link builders

    private static func zoomDeepLink(from url: URL) -> URL? {
        // https://zoom.us/j/123456789?pwd=xxx → zoommtg://zoom.us/join?action=join&confno=123456789&pwd=xxx
        let path = url.path
        guard let conf = path.split(separator: "/").last, !conf.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = "zoom.us"
        components.path = "/join"
        var items = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: String(conf))
        ]
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pwd" })?.value {
            items.append(URLQueryItem(name: "pwd", value: pwd))
        }
        components.queryItems = items
        return components.url
    }

    private static func teamsDeepLink(from url: URL) -> URL? {
        // 直接把 https 换成 msteams 常能拉起客户端。
        var absolute = url.absoluteString
        if absolute.hasPrefix("https://") {
            absolute = "msteams://" + absolute.dropFirst("https://".count)
            return URL(string: absolute)
        }
        return nil
    }

    private static func tencentDeepLink(from url: URL) -> URL? {
        // wemeet://page/inmeeting?meeting_code=xxx 形式因版本差异大，优先保留 https，已装 App 时系统会接力。
        // 若 path 含 meeting code，尝试通用 scheme。
        if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { ["meetingcode", "meeting_code", "code"].contains($0.name.lowercased()) })?.value,
           let deep = URL(string: "wemeet://page/inmeeting?meeting_code=\(code)") {
            return deep
        }
        return nil
    }

    private static func larkDeepLink(from url: URL) -> URL? {
        // lark://meeting/xxx — 路径末段常为会议号。
        let last = url.path.split(separator: "/").last.map(String.init) ?? ""
        guard !last.isEmpty,
              let deep = URL(string: "lark://client/meeting/\(last)")
        else { return nil }
        return deep
    }

    private static func dingTalkDeepLink(from url: URL) -> URL? {
        URL(string: "dingtalk://dingtalkclient/page/conference")
    }
}
