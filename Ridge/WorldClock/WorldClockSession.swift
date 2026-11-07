import Combine
import Foundation

/// 世界时钟会话：按秒刷新快照；小组件开启且有城市时申请上岛。
@MainActor
final class WorldClockSession: ObservableObject {
    static let shared = WorldClockSession()

    @Published private(set) var snapshots: [WorldClockCitySnapshot] = []
    @Published private(set) var wantsIslandDisplay = false

    private let settings = WorldClockSettings.shared
    private var timer: Timer?
    private var started = false
    private var widgetEnabled = false
    private var settingsObservers: Set<AnyCancellable> = []

    private init() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh(reason: "settings")
            }
            .store(in: &settingsObservers)
    }

    func setWidgetEnabled(_ enabled: Bool) {
        widgetEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
            wantsIslandDisplay = false
        }
        refresh(reason: "enabled")
    }

    func start() {
        guard !started else {
            refresh(reason: "resume")
            return
        }
        started = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "tick")
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        refresh(reason: "start")
        AppLog.warn("WorldClock", "世界时钟会话已启动", ["cities": settings.cities.count])
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
        AppLog.warn("WorldClock", "世界时钟会话已停止")
    }

    func refresh(reason: String) {
        let now = Date()
        let local = TimeZone.current
        snapshots = settings.cities.map { city in
            Self.makeSnapshot(
                city: city,
                now: now,
                local: local,
                use24Hour: settings.use24Hour,
                showOffset: settings.showRelativeOffset,
                isPrimary: city.id == settings.primaryCityID
            )
        }
        let shouldShow = widgetEnabled && !settings.cities.isEmpty
        if shouldShow != wantsIslandDisplay {
            wantsIslandDisplay = shouldShow
            AppLog.warn("WorldClock", shouldShow ? "申请上岛" : "撤回上岛", [
                "reason": reason,
                "cities": settings.cities.count,
                "enabled": widgetEnabled
            ])
        }
    }

    // MARK: - Formatting

    static func makeSnapshot(
        city: WorldClockCity,
        now: Date,
        local: TimeZone,
        use24Hour: Bool,
        showOffset: Bool,
        isPrimary: Bool
    ) -> WorldClockCitySnapshot {
        let tz = TimeZone(identifier: city.timeZoneID) ?? .gmt
        let timeText = formatTime(now, timeZone: tz, use24Hour: use24Hour)
        let abbr = tz.abbreviation(for: now) ?? tz.identifier
        let isDST = tz.isDaylightSavingTime(for: now)
        let offset = showOffset ? relativeOffsetBadge(now: now, cityTZ: tz, local: local) : ""
        let phase = dayPhase(now: now, latitude: city.latitude, longitude: city.longitude, timeZone: tz)
        return WorldClockCitySnapshot(
            id: city.id,
            city: city,
            timeText: timeText,
            zoneAbbreviation: abbr,
            zoneStatusText: zoneStatusText(abbr: abbr, timeZone: tz, now: now, isDST: isDST),
            isDaylightSaving: isDST,
            offsetBadge: offset,
            dayPhase: phase,
            isPrimary: isPrimary
        )
    }

    /// 夏令时：`BST 生效中`（绿）；无夏令时：`无夏令时 (JST)`；标准时：缩写（灰）。
    static func zoneStatusText(abbr: String, timeZone: TimeZone, now: Date, isDST: Bool) -> String {
        if isDST {
            return L10n.WorldClock.dstActive(abbr)
        }
        if !observesDaylightSaving(timeZone, around: now) {
            return L10n.WorldClock.noDST(abbr)
        }
        return abbr
    }

    /// 同年 1 月与 7 月 GMT 偏移不同则视为观察夏令时。
    static func observesDaylightSaving(_ timeZone: TimeZone, around date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let year = cal.component(.year, from: date)
        guard let jan = cal.date(from: DateComponents(year: year, month: 1, day: 15)),
              let jul = cal.date(from: DateComponents(year: year, month: 7, day: 15))
        else { return false }
        return timeZone.secondsFromGMT(for: jan) != timeZone.secondsFromGMT(for: jul)
    }

    static func formatTime(_ date: Date, timeZone: TimeZone, use24Hour: Bool) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    /// 如 `-7h 昨天` / `+1h 今天`。
    static func relativeOffsetBadge(now: Date, cityTZ: TimeZone, local: TimeZone) -> String {
        let citySecs = cityTZ.secondsFromGMT(for: now)
        let localSecs = local.secondsFromGMT(for: now)
        let deltaHours = Int((Double(citySecs - localSecs) / 3600.0).rounded())
        let sign = deltaHours > 0 ? "+" : ""
        let hourPart = "\(sign)\(deltaHours)h"

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = cityTZ
        let cityDay = fmt.string(from: now)
        fmt.timeZone = local
        let localDay = fmt.string(from: now)
        let dayLabel: String
        if cityDay < localDay {
            dayLabel = L10n.WorldClock.yesterday
        } else if cityDay > localDay {
            dayLabel = L10n.WorldClock.tomorrow
        } else {
            dayLabel = L10n.WorldClock.today
        }
        return "\(hourPart) (\(dayLabel))"
    }

    /// 粗略太阳高度：按当地时角 + 纬度估昼夜（无需网络）。
    static func dayPhase(
        now: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> WorldClockDayPhase {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let localHours = Double(hour) + Double(minute) / 60.0

        // 无坐标时退回钟点分段。
        if abs(latitude) < 0.01, abs(longitude) < 0.01 {
            switch localHours {
            case 5..<7: return .dawn
            case 7..<17: return .day
            case 17..<19: return .dusk
            default: return .night
            }
        }

        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: now) ?? 1)
        let declination = 23.44 * sin((360.0 / 365.0) * (dayOfYear - 81.0) * .pi / 180.0)
        let timeOffset = longitude / 15.0
        let solarTime = localHours + (Double(timeZone.secondsFromGMT(for: now)) / 3600.0 - timeOffset)
        let hourAngle = (solarTime - 12.0) * 15.0
        let latR = latitude * .pi / 180.0
        let decR = declination * .pi / 180.0
        let haR = hourAngle * .pi / 180.0
        let elevation = asin(
            sin(latR) * sin(decR) + cos(latR) * cos(decR) * cos(haR)
        ) * 180.0 / .pi

        switch elevation {
        case ..<(-6): return .night
        case ..<0: return .dusk
        case ..<6: return .dawn
        default: return .day
        }
    }
}
