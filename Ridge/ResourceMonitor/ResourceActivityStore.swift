import Foundation

/// 按日聚合击键 / 切换 / RAM 档位；热力按「本年 × 首次使用日」展示，跨年清空。
@MainActor
final class ResourceActivityStore {
    static let shared = ResourceActivityStore()

    private struct AppFocusStats {
        var name: String
        var seconds: TimeInterval = 0
        var keystrokes: Int = 0
        var switches: Int = 0
        var sessionCount: Int = 0
        var longestSession: TimeInterval = 0
        /// 当前连续驻留（切走时清零）。
        var currentStreak: TimeInterval = 0
    }

    /// 磁盘信封：兼容旧版纯数组。
    private struct DiskPayload: Codable {
        var firstUseDayKey: String
        var days: [ResourceDayAggregate]
        var timelineDayKey: String?
        var timelineSegments: [ResourceFocusTimelineSegment]?
    }

    private let fileURL: URL
    private var byDay: [String: ResourceDayAggregate] = [:]
    /// 用户首次使用资源监控的日历日（yyyy-MM-dd），跨年保留。
    private var firstUseDayKey: String = ""
    /// 今日各 App 前台累计秒（兼容旧切片 API）。
    private(set) var todayFocusSeconds: [String: (name: String, seconds: TimeInterval)] = [:]
    private var todayAppStats: [String: AppFocusStats] = [:]
    private var focusBundleID: String?
    private var focusName: String?
    /// 仅用于累加时长；tick 会前移，不能当作时序段起点。
    private var focusSince: Date?
    /// 当前连续前台段起点（切 App / 暂停才重置）。
    private var focusSegmentStart: Date?
    /// 今日已结束的时序段（按时间顺序）。
    private var todayTimelineSegments: [ResourceFocusTimelineSegment] = []
    /// 今日各整点小时击键桶（0…23 → 次数）。
    private var todayHourlyKeystrokes: [Int: Int] = [:]
    private var activeDayKey: String = ""

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Ridge/ResourceMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("daily.json")
        load()
        activeDayKey = dayKey()
        ensureFirstUseDay()
        pruneOtherYears()
    }

    func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func todayAggregate() -> ResourceDayAggregate {
        rolloverIfNeeded()
        let key = dayKey()
        return byDay[key] ?? ResourceDayAggregate(dayKey: key, keystrokes: 0, peakRamBand: 0, appSwitches: 0)
    }

    /// 本年热力：从「本年 1/1」与「首次使用日」较晚者起，到今天；跨年数据已 prune。
    func yearAggregates() -> [ResourceDayAggregate] {
        rolloverIfNeeded()
        ensureFirstUseDay()
        pruneOtherYears()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let year = cal.component(.year, from: today)
        let yearStartKey = String(format: "%04d-01-01", year)
        let rangeStartKey = max(yearStartKey, firstUseDayKey.isEmpty ? yearStartKey : firstUseDayKey)
        guard let start = date(fromDayKey: rangeStartKey) else { return [] }
        var days: [ResourceDayAggregate] = []
        var cursor = cal.startOfDay(for: start)
        while cursor <= today {
            let key = dayKey(for: cursor)
            days.append(byDay[key] ?? ResourceDayAggregate(dayKey: key, keystrokes: 0, peakRamBand: 0, appSwitches: 0))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    func addKeystrokes(_ count: Int) {
        guard count > 0 else { return }
        rolloverIfNeeded()
        var today = todayAggregate()
        today.keystrokes += count
        byDay[today.dayKey] = today
        let hour = Calendar.current.component(.hour, from: Date())
        todayHourlyKeystrokes[hour, default: 0] += count
        if let bid = focusBundleID {
            var stats = todayAppStats[bid] ?? AppFocusStats(name: focusName ?? bid)
            stats.keystrokes += count
            todayAppStats[bid] = stats
        }
        scheduleSave()
    }

    /// 今日击键最多的整点时段 `[start, end)`；并列取较早时段。无击键则 nil。
    func peakKeystrokeHourRange() -> (startHour: Int, endHour: Int)? {
        rolloverIfNeeded()
        guard let best = todayHourlyKeystrokes
            .filter({ $0.value > 0 })
            .max(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key > rhs.key
            })
        else { return nil }
        let start = best.key
        let end = (start + 1) % 24
        return (start, end)
    }

    func noteAppSwitch(bundleID: String, name: String) {
        rolloverIfNeeded()
        if focusBundleID == bundleID {
            focusName = name
            if focusSince == nil { focusSince = Date() }
            if focusSegmentStart == nil { focusSegmentStart = focusSince }
            return
        }
        endCurrentFocusSession(at: Date())
        beginFocusSession(bundleID: bundleID, name: name, countSwitch: true)
        var today = todayAggregate()
        today.appSwitches += 1
        byDay[today.dayKey] = today
        scheduleSave()
    }

    /// 不记切换：启动 / 心跳时对齐当前前台。
    func ensureFocus(bundleID: String, name: String) {
        rolloverIfNeeded()
        if focusBundleID == bundleID {
            focusName = name
            if focusSince == nil { focusSince = Date() }
            if focusSegmentStart == nil { focusSegmentStart = focusSince }
            return
        }
        endCurrentFocusSession(at: Date())
        beginFocusSession(bundleID: bundleID, name: name, countSwitch: false)
    }

    /// Ridge 自身前台：冲掉当前段并暂停，避免时长算错 App。
    func pauseFocus() {
        endCurrentFocusSession(at: Date())
        focusBundleID = nil
        focusName = nil
        focusSince = nil
    }

    func noteRamSample(percent: Double, usedBytes: UInt64) {
        rolloverIfNeeded()
        let band = ramBand(percent)
        var today = todayAggregate()
        if band > today.peakRamBand {
            today.peakRamBand = band
            byDay[today.dayKey] = today
            scheduleSave()
            AppLog.debug("ResourceMonitor", "今日 RAM 峰值档位升高", [
                "band": band,
                "percent": Int(percent.rounded()),
                "usedMB": Int(usedBytes / 1_048_576)
            ])
        }
    }

    func todayFocusSlices(limit: Int = 5) -> [ResourceFocusSlice] {
        todayFocusRanks(limit: limit).map { rank in
            ResourceFocusSlice(
                bundleID: rank.bundleID,
                name: rank.name,
                seconds: rank.seconds,
                colorIndex: rank.colorIndex
            )
        }
    }

    /// 应用聚焦驻留排行（含击键 / 切换 / 平均 / 最长）。
    func todayFocusRanks(limit: Int = 5) -> [ResourceFocusRank] {
        rolloverIfNeeded()
        flushFocus(to: Date())
        syncLegacyFocusSeconds()
        let total = max(1, todayAppStats.values.reduce(0) { $0 + $1.seconds })
        let ranked = todayAppStats
            .map { key, stats in (bundleID: key, stats: stats) }
            .sorted { $0.stats.seconds > $1.stats.seconds }
            .prefix(limit)
        return ranked.enumerated().map { index, item in
            let sessions = max(1, item.stats.sessionCount)
            let avg = item.stats.seconds / Double(sessions)
            return ResourceFocusRank(
                bundleID: item.bundleID,
                name: item.stats.name,
                category: Self.category(for: item.bundleID, name: item.stats.name),
                seconds: item.stats.seconds,
                sharePercent: (item.stats.seconds / total) * 100,
                keystrokes: item.stats.keystrokes,
                switches: item.stats.switches,
                averageSessionSeconds: avg,
                longestSessionSeconds: max(item.stats.longestSession, item.stats.currentStreak),
                colorIndex: index
            )
        }
    }

    /// 今日所有 App 驻留总秒。
    func todayTotalFocusSeconds() -> TimeInterval {
        rolloverIfNeeded()
        flushFocus(to: Date())
        return todayAppStats.values.reduce(0) { $0 + $1.seconds }
    }

    /// 今日真实时序段（含当前未结束段）；同 App 可多次交错出现。
    /// 窗口从「今日首次前台活动」起，到现在为止（不从 00:00、也不拉到 24:00）。
    /// 短间隙并入上一段（锁屏/瞬时切换不留白）；仅较长无记录空隙才露底。
    func todayFocusTimeline() -> [ResourceFocusTimelineSegment] {
        rolloverIfNeeded()
        var list = todayTimelineSegments
        if let bid = focusBundleID,
           let start = focusSegmentStart,
           let name = focusName
        {
            let end = Date()
            if end.timeIntervalSince(start) >= 0.5 {
                list.append(
                    ResourceFocusTimelineSegment(
                        id: "live-\(bid)-\(start.timeIntervalSince1970)",
                        bundleID: bid,
                        name: name,
                        start: start,
                        end: end
                    )
                )
            }
        }
        return Self.normalizeTimeline(list)
    }

    /// 合并同 App 相邻段，并填补短于 3 分钟的空隙（归入上一段）。
    private static func normalizeTimeline(
        _ raw: [ResourceFocusTimelineSegment]
    ) -> [ResourceFocusTimelineSegment] {
        let sorted = raw.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [ResourceFocusTimelineSegment] = []
        let shortGap: TimeInterval = 3 * 60
        for next in sorted.dropFirst() {
            if next.bundleID == current.bundleID, next.start <= current.end.addingTimeInterval(shortGap) {
                current.end = max(current.end, next.end)
                continue
            }
            let gap = next.start.timeIntervalSince(current.end)
            if gap > 0, gap < shortGap {
                current.end = next.start
            }
            if next.bundleID == current.bundleID, next.start <= current.end.addingTimeInterval(0.05) {
                current.end = max(current.end, next.end)
                continue
            }
            result.append(current)
            current = next
        }
        result.append(current)
        return result
    }

    /// 时序带左端锚点：今日第一段开始；尚无活动则 nil。
    func todayFocusTimelineAnchor() -> Date? {
        todayFocusTimeline().map(\.start).min()
    }

    func tickFocus() {
        rolloverIfNeeded()
        flushFocus(to: Date())
        // 只推进累加锚点，不打断时序段。
        if focusBundleID != nil {
            focusSince = Date()
        }
    }

    private func beginFocusSession(bundleID: String, name: String, countSwitch: Bool) {
        focusBundleID = bundleID
        focusName = name
        let now = Date()
        focusSince = now
        focusSegmentStart = now
        var stats = todayAppStats[bundleID] ?? AppFocusStats(name: name)
        stats.name = name
        if countSwitch {
            stats.switches += 1
            stats.sessionCount += 1
        } else if stats.sessionCount == 0 {
            stats.sessionCount = 1
        }
        stats.currentStreak = 0
        todayAppStats[bundleID] = stats
    }

    private func endCurrentFocusSession(at date: Date) {
        flushFocus(to: date)
        if let bid = focusBundleID, let segStart = focusSegmentStart {
            let duration = date.timeIntervalSince(segStart)
            if duration >= 1 {
                let name = focusName ?? bid
                todayTimelineSegments.append(
                    ResourceFocusTimelineSegment(
                        id: "\(bid)-\(segStart.timeIntervalSince1970)-\(date.timeIntervalSince1970)",
                        bundleID: bid,
                        name: name,
                        start: segStart,
                        end: date
                    )
                )
                if todayTimelineSegments.count > 2_500 {
                    todayTimelineSegments.removeFirst(todayTimelineSegments.count - 2_500)
                }
                scheduleSave()
                AppLog.debug("ResourceMonitor", "时序段已闭合", [
                    "app": name,
                    "sec": Int(duration.rounded())
                ])
            }
        }
        if let bid = focusBundleID, var stats = todayAppStats[bid] {
            stats.longestSession = max(stats.longestSession, stats.currentStreak)
            stats.currentStreak = 0
            todayAppStats[bid] = stats
        }
        focusSegmentStart = nil
    }

    private func rolloverIfNeeded() {
        let key = dayKey()
        guard key != activeDayKey else { return }
        let crossedYear = activeDayKey.prefix(4) != key.prefix(4)
        AppLog.info("ResourceMonitor", "跨日重置今日焦点与击键时段", [
            "from": activeDayKey,
            "to": key,
            "crossedYear": crossedYear
        ])
        endCurrentFocusSession(at: Date())
        todayFocusSeconds = [:]
        todayAppStats = [:]
        todayHourlyKeystrokes = [:]
        todayTimelineSegments = []
        if focusBundleID != nil {
            let now = Date()
            focusSince = now
            focusSegmentStart = now
            if let bid = focusBundleID {
                var stats = todayAppStats[bid] ?? AppFocusStats(name: focusName ?? bid)
                stats.sessionCount = max(1, stats.sessionCount)
                todayAppStats[bid] = stats
            }
        } else {
            focusSince = nil
            focusSegmentStart = nil
        }
        activeDayKey = key
        scheduleSave()
        if crossedYear {
            pruneOtherYears()
            AppLog.info("ResourceMonitor", "跨年已清空上年热力日聚合", [
                "year": String(key.prefix(4)),
                "kept": byDay.count
            ])
        }
    }

    private func ensureFirstUseDay() {
        if firstUseDayKey.isEmpty {
            firstUseDayKey = byDay.keys.min() ?? dayKey()
            AppLog.info("ResourceMonitor", "记录首次使用日", ["day": firstUseDayKey])
            scheduleSave()
        }
    }

    private func date(fromDayKey key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private func flushFocus(to date: Date) {
        guard let bid = focusBundleID, let since = focusSince else { return }
        let delta = max(0, date.timeIntervalSince(since))
        guard delta > 0 else { return }
        let name = focusName ?? bid
        var stats = todayAppStats[bid] ?? AppFocusStats(name: name)
        stats.name = name
        stats.seconds += delta
        stats.currentStreak += delta
        stats.longestSession = max(stats.longestSession, stats.currentStreak)
        if stats.sessionCount == 0 { stats.sessionCount = 1 }
        todayAppStats[bid] = stats
        todayFocusSeconds[bid] = (name, stats.seconds)
        focusSince = date
    }

    private func syncLegacyFocusSeconds() {
        todayFocusSeconds = Dictionary(uniqueKeysWithValues: todayAppStats.map { key, stats in
            (key, (stats.name, stats.seconds))
        })
    }

    private static func category(for bundleID: String, name: String) -> ResourceFocusCategory {
        let hay = (bundleID + " " + name).lowercased()
        if hay.contains("chrome") || hay.contains("safari") || hay.contains("firefox")
            || hay.contains("arc") || hay.contains("edge") || hay.contains("browser")
            || hay.contains("qqbrowser") || hay.contains("brave")
        {
            return .browser
        }
        if hay.contains("code") || hay.contains("xcode") || hay.contains("cursor")
            || hay.contains("jetbrains") || hay.contains("webstorm") || hay.contains("idea")
            || hay.contains("sublime") || hay.contains("vim") || hay.contains("neovim")
        {
            return .ide
        }
        if hay.contains("terminal") || hay.contains("iterm") || hay.contains("warp")
            || hay.contains("alacritty") || hay.contains("kitty") || hay.contains("shell")
        {
            return .terminal
        }
        return .other
    }

    private func ramBand(_ percent: Double) -> Int {
        switch percent {
        case ..<25: return 0
        case ..<50: return 1
        case ..<70: return 2
        case ..<85: return 3
        default: return 4
        }
    }

    private var saveWork: DispatchWorkItem?

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.persist()
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let payload = try? JSONDecoder().decode(DiskPayload.self, from: data) {
            firstUseDayKey = payload.firstUseDayKey
            byDay = Dictionary(uniqueKeysWithValues: payload.days.map { ($0.dayKey, $0) })
            let today = dayKey()
            if payload.timelineDayKey == today {
                todayTimelineSegments = payload.timelineSegments ?? []
            } else {
                todayTimelineSegments = []
            }
        } else if let legacy = try? JSONDecoder().decode([ResourceDayAggregate].self, from: data) {
            byDay = Dictionary(uniqueKeysWithValues: legacy.map { ($0.dayKey, $0) })
            firstUseDayKey = byDay.keys.min() ?? ""
            AppLog.info("ResourceMonitor", "活动日聚合已从旧格式迁移", [
                "days": byDay.count,
                "firstUse": firstUseDayKey
            ])
        } else {
            return
        }
        pruneOtherYears()
    }

    private func persist() {
        pruneOtherYears()
        ensureFirstUseDay()
        let payload = DiskPayload(
            firstUseDayKey: firstUseDayKey,
            days: Array(byDay.values).sorted { $0.dayKey < $1.dayKey },
            timelineDayKey: dayKey(),
            timelineSegments: todayTimelineSegments
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
        AppLog.debug("ResourceMonitor", "活动日聚合已写入", [
            "days": payload.days.count,
            "firstUse": firstUseDayKey,
            "timeline": todayTimelineSegments.count
        ])
    }

    /// 只保留本年日历日；上年及更早在跨年时清空。
    private func pruneOtherYears() {
        let yearPrefix = String(format: "%04d-", Calendar.current.component(.year, from: Date()))
        let before = byDay.count
        byDay = byDay.filter { $0.key.hasPrefix(yearPrefix) }
        if byDay.count != before {
            AppLog.debug("ResourceMonitor", "已剔除非本年热力日", [
                "removed": before - byDay.count,
                "kept": byDay.count,
                "year": String(yearPrefix.dropLast())
            ])
        }
    }
}
