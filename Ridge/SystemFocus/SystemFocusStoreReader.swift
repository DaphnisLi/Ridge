import Foundation

/// 读 `~/Library/DoNotDisturb/DB/`（需完全磁盘访问）。非公开格式，解析失败时降级。
enum SystemFocusStoreReader {
    private static var dbDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }

    static var assertionsURL: URL {
        dbDirectory.appendingPathComponent("Assertions.json")
    }

    static var modeConfigurationsURL: URL {
        dbDirectory.appendingPathComponent("ModeConfigurations.json")
    }

    /// 探测是否能读库（完全磁盘访问）。
    static func canReadStore() -> Bool {
        let url = modeConfigurationsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 从未配置过 Focus 时文件可能不存在；试探目录是否可列。
            return (try? FileManager.default.contentsOfDirectory(atPath: dbDirectory.path)) != nil
        }
        return (try? Data(contentsOf: url, options: [.mappedIfSafe])) != nil
    }

    static func readSnapshot(now: Date = Date()) -> SystemFocusSnapshot {
        let canRead = canReadStore()
        guard canRead else {
            return SystemFocusSnapshot(isActive: false, mode: nil, endsAt: nil, canReadStore: false)
        }

        let modes = readModes()
        let assertion = readActiveAssertion()
        guard let assertion else {
            return SystemFocusSnapshot(isActive: false, mode: nil, endsAt: nil, canReadStore: true)
        }

        let mode = modes[assertion.modeIdentifier]
            ?? SystemFocusModeInfo(
                modeIdentifier: assertion.modeIdentifier,
                name: fallbackName(for: assertion.modeIdentifier),
                symbolImageName: "moon.fill",
                tintColorName: "systemIndigoColor"
            )
        let endsAt = resolveEndsAt(
            assertion: assertion,
            modeTriggers: readTriggers(for: assertion.modeIdentifier),
            now: now
        )
        return SystemFocusSnapshot(
            isActive: true,
            mode: mode,
            endsAt: endsAt,
            canReadStore: true
        )
    }

    static func readModes() -> [String: SystemFocusModeInfo] {
        guard let root = readJSON(modeConfigurationsURL),
              let data = root["data"] as? [[String: Any]],
              let store = data.first,
              let configs = store["modeConfigurations"] as? [String: Any]
        else { return [:] }

        var out: [String: SystemFocusModeInfo] = [:]
        for (key, value) in configs {
            guard let cfg = value as? [String: Any],
                  let mode = cfg["mode"] as? [String: Any]
            else { continue }
            let rawName = (mode["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = (mode["symbolImageName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tint = (mode["tintColorName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let modeID = (mode["modeIdentifier"] as? String) ?? key
            // ModeConfigurations 里内置模式名为英文（如 Do Not Disturb）；展示走 L10n。
            // 用户自建模式仍用库里的自定义名。
            out[key] = SystemFocusModeInfo(
                modeIdentifier: modeID,
                name: displayName(modeIdentifier: modeID, rawName: rawName),
                symbolImageName: (symbol?.isEmpty == false) ? symbol! : "moon.fill",
                tintColorName: (tint?.isEmpty == false) ? tint! : "systemIndigoColor"
            )
        }
        return out
    }

    // MARK: - Private

    private struct ActiveAssertion {
        var modeIdentifier: String
        var reason: String
        var startReferenceDate: TimeInterval?
        var lifetime: Any?
    }

    private static func readActiveAssertion() -> ActiveAssertion? {
        guard let root = readJSON(assertionsURL),
              let data = root["data"] as? [[String: Any]],
              let store = data.first,
              let records = store["storeAssertionRecords"] as? [[String: Any]],
              let first = records.first,
              let details = first["assertionDetails"] as? [String: Any],
              let modeID = details["assertionDetailsModeIdentifier"] as? String,
              !modeID.isEmpty
        else { return nil }

        let reason = (details["assertionDetailsReason"] as? String) ?? ""
        let start = first["assertionStartDateTimestamp"] as? Double
        let lifetime = details["assertionDetailsLifetime"]
        return ActiveAssertion(
            modeIdentifier: modeID,
            reason: reason,
            startReferenceDate: start,
            lifetime: lifetime
        )
    }

    private struct ScheduleTrigger {
        var enabled: Bool
        var startMinute: Int
        var endMinute: Int
        var weekdaysMask: Int
    }

    private static func readTriggers(for modeIdentifier: String) -> [ScheduleTrigger] {
        guard let root = readJSON(modeConfigurationsURL),
              let data = root["data"] as? [[String: Any]],
              let store = data.first,
              let configs = store["modeConfigurations"] as? [String: Any],
              let cfg = configs[modeIdentifier] as? [String: Any],
              let triggersWrap = cfg["triggers"] as? [String: Any],
              let triggers = triggersWrap["triggers"] as? [[String: Any]]
        else { return [] }

        return triggers.compactMap { t in
            // enabledSetting: 2 = on（与社区脚本一致）。
            let enabledSetting = t["enabledSetting"] as? Int ?? 0
            guard enabledSetting == 2 else { return nil }
            let startH = t["timePeriodStartTimeHour"] as? Int ?? 0
            let startM = t["timePeriodStartTimeMinute"] as? Int ?? 0
            let endH = t["timePeriodEndTimeHour"] as? Int ?? 0
            let endM = t["timePeriodEndTimeMinute"] as? Int ?? 0
            let weekdays = t["timePeriodWeekdays"] as? Int ?? 127
            return ScheduleTrigger(
                enabled: true,
                startMinute: startH * 60 + startM,
                endMinute: endH * 60 + endM,
                weekdaysMask: weekdays
            )
        }
    }

    private static func resolveEndsAt(
        assertion: ActiveAssertion,
        modeTriggers: [ScheduleTrigger],
        now: Date
    ) -> Date? {
        if let fromLifetime = endsAtFromLifetime(assertion.lifetime, startReference: assertion.startReferenceDate) {
            return fromLifetime
        }
        // 日程触发：用今日（或跨午夜）结束时刻。
        if assertion.reason == "schedule" || !modeTriggers.isEmpty {
            if let scheduleEnd = scheduleEndDate(triggers: modeTriggers, now: now) {
                return scheduleEnd
            }
        }
        return nil
    }

    private static func endsAtFromLifetime(_ lifetime: Any?, startReference: TimeInterval?) -> Date? {
        guard let lifetime else { return nil }

        if let dict = lifetime as? [String: Any] {
            // DNDModeAssertionDateIntervalLifetime
            if let interval = dict["dateInterval"] as? [String: Any] {
                if let end = interval["end"] as? Double {
                    return Date(timeIntervalSinceReferenceDate: end)
                }
                if let endDate = interval["endDate"] as? Double {
                    return Date(timeIntervalSinceReferenceDate: endDate)
                }
            }
            // DNDModeAssertionDurationLifetime：秒
            if let duration = dict["duration"] as? Double, duration > 0,
               let start = startReference
            {
                return Date(timeIntervalSinceReferenceDate: start + duration)
            }
            if let duration = dict["duration"] as? Int, duration > 0,
               let start = startReference
            {
                return Date(timeIntervalSinceReferenceDate: start + Double(duration))
            }
        }

        if let duration = lifetime as? Double, duration > 0, let start = startReference {
            return Date(timeIntervalSinceReferenceDate: start + duration)
        }
        if let duration = lifetime as? Int, duration > 0, let start = startReference {
            return Date(timeIntervalSinceReferenceDate: start + Double(duration))
        }
        return nil
    }

    private static func scheduleEndDate(triggers: [ScheduleTrigger], now: Date) -> Date? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1=Sun … 7=Sat
        // Apple mask：bit0=周日 … bit6=周六（与 `date +%u` 脚本一致用 Mon=1 的另一种写法也有；
        // 这里用常见 bit：(1 << (weekday-1))）。
        let bit = 1 << (weekday - 1)
        let minuteOfDay = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        for trigger in triggers where trigger.enabled {
            guard (trigger.weekdaysMask & bit) != 0 else { continue }
            let start = trigger.startMinute
            let end = trigger.endMinute
            let inWindow: Bool
            if start < end {
                inWindow = minuteOfDay >= start && minuteOfDay < end
            } else if start > end {
                // 跨午夜
                inWindow = minuteOfDay >= start || minuteOfDay < end
            } else {
                inWindow = false
            }
            guard inWindow else { continue }

            var comps = cal.dateComponents([.year, .month, .day], from: now)
            if start < end {
                comps.hour = end / 60
                comps.minute = end % 60
                comps.second = 0
                return cal.date(from: comps)
            } else {
                // 跨午夜：结束在次日
                let day = cal.date(byAdding: .day, value: minuteOfDay >= start ? 1 : 0, to: now) ?? now
                var endComps = cal.dateComponents([.year, .month, .day], from: day)
                if minuteOfDay < end {
                    endComps = cal.dateComponents([.year, .month, .day], from: now)
                }
                endComps.hour = end / 60
                endComps.minute = end % 60
                endComps.second = 0
                return cal.date(from: endComps)
            }
        }
        return nil
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let obj = try JSONSerialization.jsonObject(with: data)
            return obj as? [String: Any]
        } catch {
            AppLog.warn("SystemFocus", "读 Focus 库失败", [
                "path": url.lastPathComponent,
                "error": error.localizedDescription
            ])
            return nil
        }
    }

    /// 内置 Focus：固定中文展示名；自建模式：用库内名称。
    private static func displayName(modeIdentifier: String, rawName: String?) -> String {
        if let builtin = builtinLocalizedName(for: modeIdentifier) {
            return builtin
        }
        if let rawName, !rawName.isEmpty {
            return rawName
        }
        return L10n.SystemFocus.fallbackGeneric
    }

    private static func builtinLocalizedName(for modeIdentifier: String) -> String? {
        switch modeIdentifier {
        case "com.apple.donotdisturb.mode.default":
            return L10n.SystemFocus.fallbackDoNotDisturb
        case "com.apple.focus.work":
            return L10n.SystemFocus.fallbackWork
        case "com.apple.focus.personal":
            return L10n.SystemFocus.fallbackPersonal
        case "com.apple.sleep.sleep-mode":
            return L10n.SystemFocus.fallbackSleep
        case "com.apple.donotdisturb.mode.driving":
            return L10n.SystemFocus.fallbackDriving
        case "com.apple.focus.fitness":
            return L10n.SystemFocus.fallbackFitness
        case "com.apple.focus.gaming":
            return L10n.SystemFocus.fallbackGaming
        case "com.apple.focus.mindfulness":
            return L10n.SystemFocus.fallbackMindfulness
        case "com.apple.focus.reading":
            return L10n.SystemFocus.fallbackReading
        default:
            return nil
        }
    }

    private static func fallbackName(for modeIdentifier: String) -> String {
        builtinLocalizedName(for: modeIdentifier) ?? L10n.SystemFocus.fallbackGeneric
    }
}
