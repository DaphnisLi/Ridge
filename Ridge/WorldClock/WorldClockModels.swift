import Foundation

/// 固钉城市条目（持久化）。
struct WorldClockCity: Identifiable, Equatable, Hashable {
    var id: String
    /// IANA 时区，如 `Europe/London`。
    var timeZoneID: String
    /// 展示用城市名（英文目录名，设置列表用）。
    var cityName: String
    /// 中文城市名（岛上副行）；空则回退 `cityName`。
    var cityNameLocalized: String
    /// 国家 / 地区短标，如 `UK`。
    var region: String
    /// 国旗 emoji。
    var flag: String
    /// 用户自定义别名；空则显示城市名。
    var alias: String
    /// 近似纬度（昼夜图标）；未知为 0。
    var latitude: Double
    /// 近似经度。
    var longitude: Double

    var displayTitle: String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? displayCityName : trimmed
    }

    var displayCityName: String {
        let trimmed = cityNameLocalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? cityName : trimmed
    }
}

extension WorldClockCity: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timeZoneID, cityName, cityNameLocalized, region, flag, alias, latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        cityName = try c.decode(String.self, forKey: .cityName)
        cityNameLocalized = try c.decodeIfPresent(String.self, forKey: .cityNameLocalized) ?? ""
        region = try c.decode(String.self, forKey: .region)
        flag = try c.decode(String.self, forKey: .flag)
        alias = try c.decodeIfPresent(String.self, forKey: .alias) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        if cityNameLocalized.isEmpty {
            cityNameLocalized = WorldClockCatalog.entries
                .first(where: { $0.cityName == cityName && $0.timeZoneID == timeZoneID })?
                .cityNameLocalized ?? ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timeZoneID, forKey: .timeZoneID)
        try c.encode(cityName, forKey: .cityName)
        try c.encode(cityNameLocalized, forKey: .cityNameLocalized)
        try c.encode(region, forKey: .region)
        try c.encode(flag, forKey: .flag)
        try c.encode(alias, forKey: .alias)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
    }
}

/// 目录检索结果。
struct WorldClockCatalogEntry: Identifiable, Hashable {
    var id: String { timeZoneID + "|" + cityName }
    var cityName: String
    /// 中文常用名。
    var cityNameLocalized: String
    var region: String
    var flag: String
    var timeZoneID: String
    var latitude: Double
    var longitude: Double
    var keywords: [String]
}

enum WorldClockDayPhase: String {
    case dawn
    case day
    case dusk
    case night

    var symbolName: String {
        switch self {
        case .dawn: return "sun.horizon.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sun.horizon.fill"
        case .night: return "moon.fill"
        }
    }

    var tint: (Double, Double, Double) {
        switch self {
        case .dawn: return (1.0, 0.75, 0.35)
        case .day: return (1.0, 0.72, 0.2)
        case .dusk: return (1.0, 0.55, 0.25)
        case .night: return (0.65, 0.7, 0.95)
        }
    }
}

/// 岛上 / 设置行实时快照。
struct WorldClockCitySnapshot: Identifiable, Equatable {
    var id: String
    var city: WorldClockCity
    var timeText: String
    var zoneAbbreviation: String
    /// 设置行右侧时区状态文案，如 `BST 生效中` / `无夏令时 (JST)`。
    var zoneStatusText: String
    /// 当前是否处于夏令时（决定绿/灰角标）。
    var isDaylightSaving: Bool
    var offsetBadge: String
    var dayPhase: WorldClockDayPhase
    var isPrimary: Bool
}
