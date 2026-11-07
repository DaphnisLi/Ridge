import Combine
import Foundation

/// 世界时钟偏好与固钉城市。
@MainActor
final class WorldClockSettings: ObservableObject {
    static let shared = WorldClockSettings()

    static let maxCities = 4

    private enum Key {
        /// v3：默认展示 3 城（别名为空）。
        static let cities = "worldClock.cities.v3"
        static let primaryID = "worldClock.primaryID.v1"
        static let use24Hour = "worldClock.use24Hour.v1"
        static let showDayNight = "worldClock.showDayNight.v1"
        static let showOffset = "worldClock.showOffset.v1"
    }

    private let defaults = UserDefaults.standard

    @Published var cities: [WorldClockCity] = [] {
        didSet { persistCities() }
    }

    @Published var primaryCityID: String? = nil {
        didSet { defaults.set(primaryCityID, forKey: Key.primaryID) }
    }

    @Published var use24Hour: Bool = true {
        didSet { defaults.set(use24Hour, forKey: Key.use24Hour) }
    }

    @Published var showDayNightIcons: Bool = true {
        didSet { defaults.set(showDayNightIcons, forKey: Key.showDayNight) }
    }

    @Published var showRelativeOffset: Bool = true {
        didSet { defaults.set(showRelativeOffset, forKey: Key.showOffset) }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.cities),
           let decoded = try? JSONDecoder().decode([WorldClockCity].self, from: data),
           !decoded.isEmpty
        {
            cities = Array(decoded.prefix(Self.maxCities))
        } else {
            cities = Self.defaultCities()
            AppLog.info("WorldClock", "使用默认城市（别名为空）", ["count": cities.count])
        }

        var primary = defaults.string(forKey: Key.primaryID) ?? cities.first?.id
        if let p = primary, !cities.contains(where: { $0.id == p }) {
            primary = cities.first?.id
        }
        primaryCityID = primary

        if defaults.object(forKey: Key.use24Hour) != nil {
            use24Hour = defaults.bool(forKey: Key.use24Hour)
        }
        if defaults.object(forKey: Key.showDayNight) != nil {
            showDayNightIcons = defaults.bool(forKey: Key.showDayNight)
        }
        if defaults.object(forKey: Key.showOffset) != nil {
            showRelativeOffset = defaults.bool(forKey: Key.showOffset)
        }
    }

    var isFull: Bool { cities.count >= Self.maxCities }

    func restoreDefaults() {
        cities = Self.defaultCities()
        primaryCityID = cities.first?.id
        use24Hour = true
        showDayNightIcons = true
        showRelativeOffset = true
        AppLog.info("WorldClock", "已恢复默认设置", ["cities": cities.count])
    }

    @discardableResult
    func addCity(_ city: WorldClockCity) -> Bool {
        guard !isFull else {
            AppLog.warn("WorldClock", "固钉已满，无法添加", ["max": Self.maxCities])
            return false
        }
        if cities.contains(where: {
            $0.timeZoneID == city.timeZoneID && $0.cityName == city.cityName
        }) {
            AppLog.info("WorldClock", "城市已存在，跳过", ["city": city.cityName])
            return false
        }
        cities.append(city)
        if primaryCityID == nil {
            primaryCityID = city.id
        }
        AppLog.info("WorldClock", "已添加城市", [
            "city": city.cityName,
            "tz": city.timeZoneID,
            "count": cities.count
        ])
        return true
    }

    func removeCity(id: String) {
        cities.removeAll { $0.id == id }
        if primaryCityID == id {
            primaryCityID = cities.first?.id
        }
        AppLog.info("WorldClock", "已移除城市", ["id": id, "count": cities.count])
    }

    func moveCity(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
        AppLog.info("WorldClock", "已调整城市顺序", ["count": cities.count])
    }

    /// 拖到目标行上交换顺序（与小组件库拖放同语义）。
    @discardableResult
    func moveCity(draggedID: String, onto targetID: String) -> Bool {
        guard draggedID != targetID,
              let from = cities.firstIndex(where: { $0.id == draggedID }),
              let to = cities.firstIndex(where: { $0.id == targetID }),
              from != to
        else { return false }
        var next = cities
        next.swapAt(from, to)
        cities = next
        AppLog.info("WorldClock", "拖拽交换城市顺序", [
            "from": draggedID,
            "onto": targetID,
            "fromIndex": from,
            "toIndex": to
        ])
        return true
    }

    func updateAlias(id: String, alias: String) {
        guard let index = cities.firstIndex(where: { $0.id == id }) else { return }
        cities[index].alias = alias
    }

    func setPrimary(id: String) {
        guard cities.contains(where: { $0.id == id }) else { return }
        primaryCityID = id
        AppLog.info("WorldClock", "已设主城市", ["id": id])
    }

    private func persistCities() {
        if let data = try? JSONEncoder().encode(cities) {
            defaults.set(data, forKey: Key.cities)
        }
    }

    private static func defaultCities() -> [WorldClockCity] {
        ["London", "San Francisco", "Tokyo"].compactMap { city in
            guard let entry = WorldClockCatalog.entries.first(where: { $0.cityName == city })
            else { return nil }
            return WorldClockCatalog.makeCity(from: entry, alias: "")
        }
    }
}
