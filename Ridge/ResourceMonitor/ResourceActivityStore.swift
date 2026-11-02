import Foundation

/// 按日聚合击键 / 切换 / RAM 档位；保留约 366 天。
@MainActor
final class ResourceActivityStore {
    static let shared = ResourceActivityStore()

    private let fileURL: URL
    private var byDay: [String: ResourceDayAggregate] = [:]
    /// 今日各 App 前台累计秒。
    private(set) var todayFocusSeconds: [String: (name: String, seconds: TimeInterval)] = [:]
    private var focusBundleID: String?
    private var focusName: String?
    private var focusSince: Date?
    private var ramSamplesToday: [ResourceRAMSample] = []
    private var activeDayKey: String = ""

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Ridge/ResourceMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("daily.json")
        load()
        activeDayKey = dayKey()
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

    func yearAggregates() -> [ResourceDayAggregate] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -365, to: today) else { return [] }
        var days: [ResourceDayAggregate] = []
        var cursor = start
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
        var today = todayAggregate()
        today.keystrokes += count
        byDay[today.dayKey] = today
        scheduleSave()
    }

    func noteAppSwitch(bundleID: String, name: String) {
        rolloverIfNeeded()
        if focusBundleID == bundleID {
            focusName = name
            if focusSince == nil { focusSince = Date() }
            return
        }
        flushFocus(to: Date())
        focusBundleID = bundleID
        focusName = name
        focusSince = Date()
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
            return
        }
        flushFocus(to: Date())
        focusBundleID = bundleID
        focusName = name
        focusSince = Date()
    }

    /// Ridge 自身前台：冲掉当前段并暂停，避免时长算错 App。
    func pauseFocus() {
        flushFocus(to: Date())
        focusBundleID = nil
        focusName = nil
        focusSince = nil
    }

    func noteRamSample(percent: Double, usedBytes: UInt64) {
        rolloverIfNeeded()
        let gb = Double(usedBytes) / 1_073_741_824.0
        ramSamplesToday.append(ResourceRAMSample(at: Date(), usedGB: gb, percent: percent))
        if ramSamplesToday.count > 2_000 {
            ramSamplesToday.removeFirst(ramSamplesToday.count - 2_000)
        }
        let band = ramBand(percent)
        var today = todayAggregate()
        if band > today.peakRamBand {
            today.peakRamBand = band
            byDay[today.dayKey] = today
            scheduleSave()
        }
    }

    /// 今日 RAM 波形采样。
    func todayRamSamples() -> [ResourceRAMSample] {
        rolloverIfNeeded()
        return ramSamplesToday
    }

    func todayFocusSlices(limit: Int = 5) -> [ResourceFocusSlice] {
        rolloverIfNeeded()
        flushFocus(to: Date())
        let ranked = todayFocusSeconds
            .map { (bundleID: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(limit)
        return ranked.enumerated().map { index, item in
            ResourceFocusSlice(
                bundleID: item.bundleID,
                name: item.name,
                seconds: item.seconds,
                colorIndex: index
            )
        }
    }

    func tickFocus() {
        rolloverIfNeeded()
        flushFocus(to: Date())
        if focusBundleID != nil {
            focusSince = Date()
        }
    }

    private func rolloverIfNeeded() {
        let key = dayKey()
        guard key != activeDayKey else { return }
        AppLog.info("ResourceMonitor", "跨日重置今日焦点与 RAM 波形", [
            "from": activeDayKey,
            "to": key
        ])
        flushFocus(to: Date())
        todayFocusSeconds = [:]
        ramSamplesToday = []
        focusSince = focusBundleID == nil ? nil : Date()
        activeDayKey = key
    }

    private func flushFocus(to date: Date) {
        guard let bid = focusBundleID, let since = focusSince else { return }
        let delta = max(0, date.timeIntervalSince(since))
        guard delta > 0 else { return }
        let name = focusName ?? bid
        let prev = todayFocusSeconds[bid]?.seconds ?? 0
        todayFocusSeconds[bid] = (name, prev + delta)
        focusSince = date
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
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ResourceDayAggregate].self, from: data)
        else { return }
        byDay = Dictionary(uniqueKeysWithValues: decoded.map { ($0.dayKey, $0) })
        pruneOld()
    }

    private func persist() {
        pruneOld()
        let list = Array(byDay.values).sorted { $0.dayKey < $1.dayKey }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: .atomic)
        AppLog.debug("ResourceMonitor", "活动日聚合已写入", ["days": list.count])
    }

    private func pruneOld() {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -370, to: Date()) else { return }
        let cutoffKey = dayKey(for: cutoff)
        byDay = byDay.filter { $0.key >= cutoffKey }
    }
}
