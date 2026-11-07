import Foundation

/// 世界时钟城市目录：精选城市（中英关键词 / 国旗 / 经纬）+ 系统全部 IANA 时区兜底。
enum WorldClockCatalog {
    static let entries: [WorldClockCatalogEntry] = buildEntries()

    // MARK: - Build

    private static func buildEntries() -> [WorldClockCatalogEntry] {
        let curated = curatedEntries
        var coveredZones = Set(curated.map(\.timeZoneID))
        var result = curated

        for zoneID in TimeZone.knownTimeZoneIdentifiers.sorted() {
            guard !coveredZones.contains(zoneID) else { continue }
            guard let synthetic = synthesize(from: zoneID) else { continue }
            coveredZones.insert(zoneID)
            result.append(synthetic)
        }
        return result
    }

    /// 从 IANA id 生成兜底条目（无精选坐标时昼夜按钟点估算）。
    private static func synthesize(from zoneID: String) -> WorldClockCatalogEntry? {
        let parts = zoneID.split(separator: "/").map(String.init)
        guard let last = parts.last else { return nil }
        let city = last.replacingOccurrences(of: "_", with: " ")
        let region = parts.count >= 2 ? parts[parts.count - 2].replacingOccurrences(of: "_", with: " ") : (parts.first ?? "")
        let meta = zoneMeta(for: zoneID)
        var keywords = [
            city.lowercased(),
            zoneID.lowercased(),
            last.lowercased(),
            last.replacingOccurrences(of: "_", with: " ").lowercased(),
        ]
        if let abbr = TimeZone(identifier: zoneID)?.abbreviation()?.lowercased() {
            keywords.append(abbr)
        }
        keywords.append(contentsOf: meta.extraKeywords)
        return WorldClockCatalogEntry(
            cityName: city,
            cityNameLocalized: meta.zhName ?? city,
            region: meta.regionLabel.isEmpty ? region : meta.regionLabel,
            flag: meta.flag,
            timeZoneID: zoneID,
            latitude: 0,
            longitude: 0,
            keywords: Array(Set(keywords))
        )
    }

    private struct ZoneMeta {
        var flag: String
        var regionLabel: String
        var zhName: String?
        var extraKeywords: [String]
    }

    private static func zoneMeta(for zoneID: String) -> ZoneMeta {
        let id = zoneID.lowercased()
        // 粗分国旗 / 地区标签；精选条目会覆盖主流城市。
        if id.hasPrefix("asia/shanghai") || id.hasPrefix("asia/chongqing") || id.hasPrefix("asia/harbin")
            || id.hasPrefix("asia/urumqi") || id.hasPrefix("asia/kashgar")
        {
            return ZoneMeta(flag: "🇨🇳", regionLabel: "CN", zhName: nil, extraKeywords: ["中国", "china"])
        }
        if id.hasPrefix("asia/hong_kong") {
            return ZoneMeta(flag: "🇭🇰", regionLabel: "HK", zhName: "香港", extraKeywords: ["香港", "hong kong"])
        }
        if id.hasPrefix("asia/taipei") {
            return ZoneMeta(flag: "🇹🇼", regionLabel: "TW", zhName: "台北", extraKeywords: ["台北", "台湾"])
        }
        if id.hasPrefix("asia/tokyo") {
            return ZoneMeta(flag: "🇯🇵", regionLabel: "JP", zhName: nil, extraKeywords: ["日本", "japan"])
        }
        if id.hasPrefix("asia/seoul") {
            return ZoneMeta(flag: "🇰🇷", regionLabel: "KR", zhName: nil, extraKeywords: ["韩国", "korea"])
        }
        if id.hasPrefix("asia/singapore") {
            return ZoneMeta(flag: "🇸🇬", regionLabel: "SG", zhName: "新加坡", extraKeywords: ["新加坡"])
        }
        if id.hasPrefix("europe/") {
            return ZoneMeta(flag: "🇪🇺", regionLabel: "Europe", zhName: nil, extraKeywords: ["欧洲", "europe"])
        }
        if id.hasPrefix("america/") {
            return ZoneMeta(flag: "🌎", regionLabel: "Americas", zhName: nil, extraKeywords: ["美洲", "america"])
        }
        if id.hasPrefix("africa/") {
            return ZoneMeta(flag: "🌍", regionLabel: "Africa", zhName: nil, extraKeywords: ["非洲", "africa"])
        }
        if id.hasPrefix("australia/") {
            return ZoneMeta(flag: "🇦🇺", regionLabel: "AU", zhName: nil, extraKeywords: ["澳洲", "australia"])
        }
        if id.hasPrefix("pacific/") {
            return ZoneMeta(flag: "🌐", regionLabel: "Pacific", zhName: nil, extraKeywords: ["太平洋", "pacific"])
        }
        if id.hasPrefix("atlantic/") {
            return ZoneMeta(flag: "🌐", regionLabel: "Atlantic", zhName: nil, extraKeywords: ["大西洋", "atlantic"])
        }
        if id.hasPrefix("indian/") {
            return ZoneMeta(flag: "🌐", regionLabel: "Indian Ocean", zhName: nil, extraKeywords: ["印度洋"])
        }
        if id.hasPrefix("arctic/") || id.hasPrefix("antarctica/") {
            return ZoneMeta(flag: "🌐", regionLabel: "Polar", zhName: nil, extraKeywords: [])
        }
        return ZoneMeta(flag: "🌐", regionLabel: "", zhName: nil, extraKeywords: [])
    }

    private static func entry(
        _ city: String,
        _ zh: String,
        _ region: String,
        _ flag: String,
        _ tz: String,
        _ lat: Double,
        _ lon: Double,
        _ keywords: [String]
    ) -> WorldClockCatalogEntry {
        var keys = keywords
        keys.append(city)
        keys.append(zh)
        keys.append(tz)
        if let abbr = TimeZone(identifier: tz)?.abbreviation()?.lowercased() {
            keys.append(abbr)
        }
        return WorldClockCatalogEntry(
            cityName: city,
            cityNameLocalized: zh,
            region: region,
            flag: flag,
            timeZoneID: tz,
            latitude: lat,
            longitude: lon,
            keywords: Array(Set(keys.map { $0.lowercased() }))
        )
    }

    // MARK: - Search

    static func search(_ query: String, limit: Int = 24) -> [WorldClockCatalogEntry] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let q = raw.lowercased()
        let qCompact = q.replacingOccurrences(of: " ", with: "")
        let qUnderscore = q.replacingOccurrences(of: " ", with: "_")

        let scored = entries.compactMap { entry -> (Int, WorldClockCatalogEntry)? in
            let city = entry.cityName.lowercased()
            let zh = entry.cityNameLocalized.lowercased()
            let tz = entry.timeZoneID.lowercased()
            let tzTail = tz.split(separator: "/").last.map(String.init) ?? ""
            let region = entry.region.lowercased()
            let keys = entry.keywords.map { $0.lowercased() }

            if city == q || zh == q { return (0, entry) }
            if keys.contains(q) { return (1, entry) }
            if city.hasPrefix(q) || zh.hasPrefix(q) { return (2, entry) }
            if tz == q || tz.hasSuffix("/" + qUnderscore) || tzTail == qUnderscore { return (3, entry) }
            if keys.contains(where: { $0.hasPrefix(q) }) { return (4, entry) }
            if city.contains(q) || zh.contains(q) || region.contains(q) { return (5, entry) }
            if tz.contains(qUnderscore) || tz.contains(qCompact) || tzTail.contains(qUnderscore) {
                return (6, entry)
            }
            if keys.contains(where: { $0.contains(q) }) { return (7, entry) }
            // 时区缩写：pst / cet / jst …
            if q.count >= 2, q.count <= 5,
               let abbr = TimeZone(identifier: entry.timeZoneID)?.abbreviation()?.lowercased(),
               abbr == q || abbr.contains(q)
            {
                return (8, entry)
            }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            // 有真实经纬的精选优先
            let lhsCurated = abs(lhs.1.latitude) + abs(lhs.1.longitude) > 0.01
            let rhsCurated = abs(rhs.1.latitude) + abs(rhs.1.longitude) > 0.01
            if lhsCurated != rhsCurated { return lhsCurated && !rhsCurated }
            return lhs.1.cityName.localizedCaseInsensitiveCompare(rhs.1.cityName) == .orderedAscending
        }

        var seen = Set<String>()
        var out: [WorldClockCatalogEntry] = []
        for (_, entry) in scored {
            let key = entry.cityName + "|" + entry.timeZoneID + "|" + entry.region
            guard seen.insert(key).inserted else { continue }
            out.append(entry)
            if out.count >= limit { break }
        }
        return out
    }

    static func makeCity(from entry: WorldClockCatalogEntry, alias: String = "") -> WorldClockCity {
        WorldClockCity(
            id: UUID().uuidString,
            timeZoneID: entry.timeZoneID,
            cityName: entry.cityName,
            cityNameLocalized: entry.cityNameLocalized,
            region: entry.region,
            flag: entry.flag,
            alias: alias,
            latitude: entry.latitude,
            longitude: entry.longitude
        )
    }

    // MARK: - Curated（主流城市 + 中文检索）

    private static var curatedEntries: [WorldClockCatalogEntry] {
        [
            // —— 中国大陆 / 港澳台 ——
            entry("Beijing", "北京", "CN", "🇨🇳", "Asia/Shanghai", 39.90, 116.40, ["beijing", "bj", "中国", "china", "cst"]),
            entry("Shanghai", "上海", "CN", "🇨🇳", "Asia/Shanghai", 31.23, 121.47, ["shanghai", "sh", "魔都"]),
            entry("Guangzhou", "广州", "CN", "🇨🇳", "Asia/Shanghai", 23.13, 113.26, ["guangzhou", "gz", "羊城"]),
            entry("Shenzhen", "深圳", "CN", "🇨🇳", "Asia/Shanghai", 22.54, 114.06, ["shenzhen", "sz", "鹏城"]),
            entry("Hangzhou", "杭州", "CN", "🇨🇳", "Asia/Shanghai", 30.27, 120.15, ["hangzhou", "hz"]),
            entry("Nanjing", "南京", "CN", "🇨🇳", "Asia/Shanghai", 32.06, 118.80, ["nanjing", "nj"]),
            entry("Chengdu", "成都", "CN", "🇨🇳", "Asia/Shanghai", 30.57, 104.07, ["chengdu", "cd", "蓉城"]),
            entry("Chongqing", "重庆", "CN", "🇨🇳", "Asia/Shanghai", 29.56, 106.55, ["chongqing", "cq"]),
            entry("Wuhan", "武汉", "CN", "🇨🇳", "Asia/Shanghai", 30.59, 114.31, ["wuhan", "wh"]),
            entry("Xi'an", "西安", "CN", "🇨🇳", "Asia/Shanghai", 34.34, 108.94, ["xian", "xi'an", "xa"]),
            entry("Suzhou", "苏州", "CN", "🇨🇳", "Asia/Shanghai", 31.30, 120.62, ["suzhou"]),
            entry("Tianjin", "天津", "CN", "🇨🇳", "Asia/Shanghai", 39.13, 117.20, ["tianjin", "tj"]),
            entry("Qingdao", "青岛", "CN", "🇨🇳", "Asia/Shanghai", 36.07, 120.38, ["qingdao", "qd"]),
            entry("Dalian", "大连", "CN", "🇨🇳", "Asia/Shanghai", 38.91, 121.61, ["dalian", "dl"]),
            entry("Xiamen", "厦门", "CN", "🇨🇳", "Asia/Shanghai", 24.48, 118.09, ["xiamen", "xm"]),
            entry("Fuzhou", "福州", "CN", "🇨🇳", "Asia/Shanghai", 26.07, 119.30, ["fuzhou", "fz"]),
            entry("Changsha", "长沙", "CN", "🇨🇳", "Asia/Shanghai", 28.23, 112.94, ["changsha"]),
            entry("Zhengzhou", "郑州", "CN", "🇨🇳", "Asia/Shanghai", 34.75, 113.65, ["zhengzhou"]),
            entry("Jinan", "济南", "CN", "🇨🇳", "Asia/Shanghai", 36.65, 117.12, ["jinan"]),
            entry("Hefei", "合肥", "CN", "🇨🇳", "Asia/Shanghai", 31.82, 117.23, ["hefei"]),
            entry("Kunming", "昆明", "CN", "🇨🇳", "Asia/Shanghai", 25.04, 102.71, ["kunming"]),
            entry("Nanning", "南宁", "CN", "🇨🇳", "Asia/Shanghai", 22.82, 108.37, ["nanning"]),
            entry("Harbin", "哈尔滨", "CN", "🇨🇳", "Asia/Shanghai", 45.80, 126.53, ["harbin", "haerbin"]),
            entry("Shenyang", "沈阳", "CN", "🇨🇳", "Asia/Shanghai", 41.80, 123.43, ["shenyang"]),
            entry("Changchun", "长春", "CN", "🇨🇳", "Asia/Shanghai", 43.82, 125.32, ["changchun"]),
            entry("Urumqi", "乌鲁木齐", "CN", "🇨🇳", "Asia/Urumqi", 43.83, 87.62, ["urumqi", "wulumuqi", "新疆"]),
            entry("Lhasa", "拉萨", "CN", "🇨🇳", "Asia/Shanghai", 29.65, 91.17, ["lhasa", "lasa", "西藏"]),
            entry("Hong Kong", "香港", "HK", "🇭🇰", "Asia/Hong_Kong", 22.32, 114.17, ["hong kong", "hk", "hkt", "香江"]),
            entry("Macau", "澳门", "MO", "🇲🇴", "Asia/Macau", 22.20, 113.54, ["macau", "macao", "mo"]),
            entry("Taipei", "台北", "TW", "🇹🇼", "Asia/Taipei", 25.03, 121.57, ["taipei", "taiwan", "台湾", "cst"]),
            entry("Kaohsiung", "高雄", "TW", "🇹🇼", "Asia/Taipei", 22.63, 120.30, ["kaohsiung", "gaoxiong"]),
            entry("Taichung", "台中", "TW", "🇹🇼", "Asia/Taipei", 24.15, 120.67, ["taichung", "taizhong"]),

            // —— 日本 / 韩国 / 东南亚 ——
            entry("Tokyo", "东京", "JP", "🇯🇵", "Asia/Tokyo", 35.68, 139.69, ["tokyo", "jst", "日本", "japan"]),
            entry("Osaka", "大阪", "JP", "🇯🇵", "Asia/Tokyo", 34.69, 135.50, ["osaka"]),
            entry("Kyoto", "京都", "JP", "🇯🇵", "Asia/Tokyo", 35.01, 135.77, ["kyoto"]),
            entry("Nagoya", "名古屋", "JP", "🇯🇵", "Asia/Tokyo", 35.18, 136.91, ["nagoya"]),
            entry("Fukuoka", "福冈", "JP", "🇯🇵", "Asia/Tokyo", 33.59, 130.40, ["fukuoka"]),
            entry("Sapporo", "札幌", "JP", "🇯🇵", "Asia/Tokyo", 43.06, 141.35, ["sapporo"]),
            entry("Seoul", "首尔", "KR", "🇰🇷", "Asia/Seoul", 37.57, 126.98, ["seoul", "kst", "韩国", "korea", "漢城"]),
            entry("Busan", "釜山", "KR", "🇰🇷", "Asia/Seoul", 35.18, 129.08, ["busan", "pusan"]),
            entry("Singapore", "新加坡", "SG", "🇸🇬", "Asia/Singapore", 1.35, 103.82, ["singapore", "sg", "sgt"]),
            entry("Bangkok", "曼谷", "TH", "🇹🇭", "Asia/Bangkok", 13.76, 100.50, ["bangkok", "thai", "泰国"]),
            entry("Chiang Mai", "清迈", "TH", "🇹🇭", "Asia/Bangkok", 18.79, 98.99, ["chiang mai", "qingmai"]),
            entry("Jakarta", "雅加达", "ID", "🇮🇩", "Asia/Jakarta", -6.21, 106.85, ["jakarta", "wib", "印尼"]),
            entry("Bali", "巴厘岛", "ID", "🇮🇩", "Asia/Makassar", -8.34, 115.09, ["bali", "denpasar", "巴厘"]),
            entry("Manila", "马尼拉", "PH", "🇵🇭", "Asia/Manila", 14.60, 120.98, ["manila", "philippines", "菲律宾"]),
            entry("Kuala Lumpur", "吉隆坡", "MY", "🇲🇾", "Asia/Kuala_Lumpur", 3.14, 101.69, ["kuala lumpur", "kl", "malaysia", "马来"]),
            entry("Penang", "槟城", "MY", "🇲🇾", "Asia/Kuala_Lumpur", 5.41, 100.33, ["penang", "乔治市"]),
            entry("Ho Chi Minh City", "胡志明市", "VN", "🇻🇳", "Asia/Ho_Chi_Minh", 10.82, 106.63, ["ho chi minh", "saigon", "西贡", "hcmc"]),
            entry("Hanoi", "河内", "VN", "🇻🇳", "Asia/Bangkok", 21.03, 105.85, ["hanoi", "越南", "vietnam"]),
            entry("Phnom Penh", "金边", "KH", "🇰🇭", "Asia/Phnom_Penh", 11.56, 104.93, ["phnom penh", "cambodia", "柬埔寨"]),
            entry("Yangon", "仰光", "MM", "🇲🇲", "Asia/Yangon", 16.87, 96.20, ["yangon", "rangoon", "myanmar", "缅甸"]),
            entry("Vientiane", "万象", "LA", "🇱🇦", "Asia/Vientiane", 17.98, 102.63, ["vientiane", "laos", "老挝"]),

            // —— 南亚 / 中亚 ——
            entry("Mumbai", "孟买", "IN", "🇮🇳", "Asia/Kolkata", 19.08, 72.88, ["mumbai", "bombay", "ist", "印度"]),
            entry("New Delhi", "新德里", "IN", "🇮🇳", "Asia/Kolkata", 28.61, 77.21, ["new delhi", "delhi", "德里"]),
            entry("Bengaluru", "班加罗尔", "IN", "🇮🇳", "Asia/Kolkata", 12.97, 77.59, ["bengaluru", "bangalore", "班加罗尔"]),
            entry("Hyderabad", "海得拉巴", "IN", "🇮🇳", "Asia/Kolkata", 17.39, 78.49, ["hyderabad"]),
            entry("Chennai", "金奈", "IN", "🇮🇳", "Asia/Kolkata", 13.08, 80.27, ["chennai", "madras"]),
            entry("Kolkata", "加尔各答", "IN", "🇮🇳", "Asia/Kolkata", 22.57, 88.36, ["kolkata", "calcutta"]),
            entry("Pune", "浦那", "IN", "🇮🇳", "Asia/Kolkata", 18.52, 73.86, ["pune"]),
            entry("Islamabad", "伊斯兰堡", "PK", "🇵🇰", "Asia/Karachi", 33.68, 73.05, ["islamabad", "pakistan", "巴基斯坦"]),
            entry("Karachi", "卡拉奇", "PK", "🇵🇰", "Asia/Karachi", 24.86, 67.00, ["karachi"]),
            entry("Lahore", "拉合尔", "PK", "🇵🇰", "Asia/Karachi", 31.52, 74.36, ["lahore"]),
            entry("Dhaka", "达卡", "BD", "🇧🇩", "Asia/Dhaka", 23.81, 90.41, ["dhaka", "bangladesh", "孟加拉"]),
            entry("Colombo", "科伦坡", "LK", "🇱🇰", "Asia/Colombo", 6.93, 79.85, ["colombo", "sri lanka", "斯里兰卡"]),
            entry("Kathmandu", "加德满都", "NP", "🇳🇵", "Asia/Kathmandu", 27.72, 85.32, ["kathmandu", "nepal", "尼泊尔"]),
            entry("Almaty", "阿拉木图", "KZ", "🇰🇿", "Asia/Almaty", 43.22, 76.85, ["almaty", "kazakhstan", "哈萨克"]),
            entry("Tashkent", "塔什干", "UZ", "🇺🇿", "Asia/Tashkent", 41.30, 69.24, ["tashkent", "uzbekistan", "乌兹别克"]),

            // —— 中东 ——
            entry("Dubai", "迪拜", "AE", "🇦🇪", "Asia/Dubai", 25.20, 55.27, ["dubai", "uae", "gst", "阿联酋"]),
            entry("Abu Dhabi", "阿布扎比", "AE", "🇦🇪", "Asia/Dubai", 24.45, 54.38, ["abu dhabi"]),
            entry("Riyadh", "利雅得", "SA", "🇸🇦", "Asia/Riyadh", 24.71, 46.68, ["riyadh", "saudi", "沙特"]),
            entry("Jeddah", "吉达", "SA", "🇸🇦", "Asia/Riyadh", 21.49, 39.19, ["jeddah"]),
            entry("Doha", "多哈", "QA", "🇶🇦", "Asia/Qatar", 25.29, 51.53, ["doha", "qatar", "卡塔尔"]),
            entry("Kuwait City", "科威特城", "KW", "🇰🇼", "Asia/Kuwait", 29.38, 47.99, ["kuwait"]),
            entry("Manama", "麦纳麦", "BH", "🇧🇭", "Asia/Bahrain", 26.23, 50.59, ["manama", "bahrain", "巴林"]),
            entry("Muscat", "马斯喀特", "OM", "🇴🇲", "Asia/Muscat", 23.59, 58.41, ["muscat", "oman", "阿曼"]),
            entry("Tehran", "德黑兰", "IR", "🇮🇷", "Asia/Tehran", 35.69, 51.39, ["tehran", "iran", "伊朗"]),
            entry("Baghdad", "巴格达", "IQ", "🇮🇶", "Asia/Baghdad", 33.32, 44.37, ["baghdad", "iraq", "伊拉克"]),
            entry("Jerusalem", "耶路撒冷", "IL", "🇮🇱", "Asia/Jerusalem", 31.77, 35.23, ["jerusalem", "israel", "以色列"]),
            entry("Tel Aviv", "特拉维夫", "IL", "🇮🇱", "Asia/Jerusalem", 32.09, 34.78, ["tel aviv", "tlv"]),
            entry("Amman", "安曼", "JO", "🇯🇴", "Asia/Amman", 31.95, 35.91, ["amman", "jordan", "约旦"]),
            entry("Beirut", "贝鲁特", "LB", "🇱🇧", "Asia/Beirut", 33.89, 35.50, ["beirut", "lebanon", "黎巴嫩"]),

            // —— 欧洲 ——
            entry("London", "伦敦", "UK", "🇬🇧", "Europe/London", 51.51, -0.13, ["london", "uk", "bst", "gmt", "英国"]),
            entry("Manchester", "曼彻斯特", "UK", "🇬🇧", "Europe/London", 53.48, -2.24, ["manchester"]),
            entry("Edinburgh", "爱丁堡", "UK", "🇬🇧", "Europe/London", 55.95, -3.19, ["edinburgh"]),
            entry("Dublin", "都柏林", "IE", "🇮🇪", "Europe/Dublin", 53.35, -6.26, ["dublin", "ireland", "爱尔兰", "ist"]),
            entry("Paris", "巴黎", "FR", "🇫🇷", "Europe/Paris", 48.86, 2.35, ["paris", "cet", "cest", "法国"]),
            entry("Lyon", "里昂", "FR", "🇫🇷", "Europe/Paris", 45.76, 4.84, ["lyon"]),
            entry("Marseille", "马赛", "FR", "🇫🇷", "Europe/Paris", 43.30, 5.37, ["marseille"]),
            entry("Berlin", "柏林", "DE", "🇩🇪", "Europe/Berlin", 52.52, 13.41, ["berlin", "germany", "德国"]),
            entry("Munich", "慕尼黑", "DE", "🇩🇪", "Europe/Berlin", 48.14, 11.58, ["munich", "muenchen", "münchen"]),
            entry("Frankfurt", "法兰克福", "DE", "🇩🇪", "Europe/Berlin", 50.11, 8.68, ["frankfurt"]),
            entry("Hamburg", "汉堡", "DE", "🇩🇪", "Europe/Berlin", 53.55, 9.99, ["hamburg"]),
            entry("Amsterdam", "阿姆斯特丹", "NL", "🇳🇱", "Europe/Amsterdam", 52.37, 4.90, ["amsterdam", "netherlands", "荷兰"]),
            entry("Rotterdam", "鹿特丹", "NL", "🇳🇱", "Europe/Amsterdam", 51.92, 4.48, ["rotterdam"]),
            entry("Brussels", "布鲁塞尔", "BE", "🇧🇪", "Europe/Brussels", 50.85, 4.35, ["brussels", "belgium", "比利时"]),
            entry("Zurich", "苏黎世", "CH", "🇨🇭", "Europe/Zurich", 47.38, 8.54, ["zurich", "switzerland", "瑞士"]),
            entry("Geneva", "日内瓦", "CH", "🇨🇭", "Europe/Zurich", 46.20, 6.14, ["geneva", "genève"]),
            entry("Vienna", "维也纳", "AT", "🇦🇹", "Europe/Vienna", 48.21, 16.37, ["vienna", "wien", "austria", "奥地利"]),
            entry("Madrid", "马德里", "ES", "🇪🇸", "Europe/Madrid", 40.42, -3.70, ["madrid", "spain", "西班牙"]),
            entry("Barcelona", "巴塞罗那", "ES", "🇪🇸", "Europe/Madrid", 41.39, 2.17, ["barcelona"]),
            entry("Lisbon", "里斯本", "PT", "🇵🇹", "Europe/Lisbon", 38.72, -9.14, ["lisbon", "portugal", "葡萄牙", "wet"]),
            entry("Rome", "罗马", "IT", "🇮🇹", "Europe/Rome", 41.90, 12.50, ["rome", "roma", "italy", "意大利"]),
            entry("Milan", "米兰", "IT", "🇮🇹", "Europe/Rome", 45.46, 9.19, ["milan", "milano"]),
            entry("Florence", "佛罗伦萨", "IT", "🇮🇹", "Europe/Rome", 43.77, 11.26, ["florence", "firenze"]),
            entry("Venice", "威尼斯", "IT", "🇮🇹", "Europe/Rome", 45.44, 12.32, ["venice", "venezia"]),
            entry("Athens", "雅典", "GR", "🇬🇷", "Europe/Athens", 37.98, 23.73, ["athens", "greece", "希腊", "eet"]),
            entry("Istanbul", "伊斯坦布尔", "TR", "🇹🇷", "Europe/Istanbul", 41.01, 28.98, ["istanbul", "turkey", "土耳其"]),
            entry("Ankara", "安卡拉", "TR", "🇹🇷", "Europe/Istanbul", 39.93, 32.86, ["ankara"]),
            entry("Moscow", "莫斯科", "RU", "🇷🇺", "Europe/Moscow", 55.76, 37.62, ["moscow", "msk", "russia", "俄罗斯"]),
            entry("Saint Petersburg", "圣彼得堡", "RU", "🇷🇺", "Europe/Moscow", 59.93, 30.34, ["saint petersburg", "st petersburg", "彼得堡"]),
            entry("Stockholm", "斯德哥尔摩", "SE", "🇸🇪", "Europe/Stockholm", 59.33, 18.07, ["stockholm", "sweden", "瑞典"]),
            entry("Oslo", "奥斯陆", "NO", "🇳🇴", "Europe/Oslo", 59.91, 10.75, ["oslo", "norway", "挪威"]),
            entry("Copenhagen", "哥本哈根", "DK", "🇩🇰", "Europe/Copenhagen", 55.68, 12.57, ["copenhagen", "denmark", "丹麦"]),
            entry("Helsinki", "赫尔辛基", "FI", "🇫🇮", "Europe/Helsinki", 60.17, 24.94, ["helsinki", "finland", "芬兰"]),
            entry("Warsaw", "华沙", "PL", "🇵🇱", "Europe/Warsaw", 52.23, 21.01, ["warsaw", "poland", "波兰"]),
            entry("Prague", "布拉格", "CZ", "🇨🇿", "Europe/Prague", 50.08, 14.44, ["prague", "praha", "czech", "捷克"]),
            entry("Budapest", "布达佩斯", "HU", "🇭🇺", "Europe/Budapest", 47.50, 19.04, ["budapest", "hungary", "匈牙利"]),
            entry("Bucharest", "布加勒斯特", "RO", "🇷🇴", "Europe/Bucharest", 44.43, 26.10, ["bucharest", "romania", "罗马尼亚"]),
            entry("Sofia", "索非亚", "BG", "🇧🇬", "Europe/Sofia", 42.70, 23.32, ["sofia", "bulgaria", "保加利亚"]),
            entry("Belgrade", "贝尔格莱德", "RS", "🇷🇸", "Europe/Belgrade", 44.79, 20.45, ["belgrade", "serbia", "塞尔维亚"]),
            entry("Zagreb", "萨格勒布", "HR", "🇭🇷", "Europe/Zagreb", 45.82, 15.98, ["zagreb", "croatia", "克罗地亚"]),
            entry("Kyiv", "基辅", "UA", "🇺🇦", "Europe/Kyiv", 50.45, 30.52, ["kyiv", "kiev", "ukraine", "乌克兰"]),
            entry("Reykjavik", "雷克雅未克", "IS", "🇮🇸", "Atlantic/Reykjavik", 64.15, -21.94, ["reykjavik", "iceland", "冰岛"]),

            // —— 非洲 ——
            entry("Cairo", "开罗", "EG", "🇪🇬", "Africa/Cairo", 30.04, 31.24, ["cairo", "egypt", "埃及"]),
            entry("Johannesburg", "约翰内斯堡", "ZA", "🇿🇦", "Africa/Johannesburg", -26.20, 28.05, ["johannesburg", "joburg", "south africa", "南非"]),
            entry("Cape Town", "开普敦", "ZA", "🇿🇦", "Africa/Johannesburg", -33.92, 18.42, ["cape town"]),
            entry("Lagos", "拉各斯", "NG", "🇳🇬", "Africa/Lagos", 6.52, 3.38, ["lagos", "nigeria", "尼日利亚"]),
            entry("Nairobi", "内罗毕", "KE", "🇰🇪", "Africa/Nairobi", -1.29, 36.82, ["nairobi", "kenya", "肯尼亚"]),
            entry("Casablanca", "卡萨布兰卡", "MA", "🇲🇦", "Africa/Casablanca", 33.57, -7.59, ["casablanca", "morocco", "摩洛哥"]),
            entry("Accra", "阿克拉", "GH", "🇬🇭", "Africa/Accra", 5.60, -0.19, ["accra", "ghana", "加纳"]),
            entry("Addis Ababa", "亚的斯亚贝巴", "ET", "🇪🇹", "Africa/Addis_Ababa", 9.03, 38.74, ["addis ababa", "ethiopia", "埃塞"]),
            entry("Dar es Salaam", "达累斯萨拉姆", "TZ", "🇹🇿", "Africa/Dar_es_Salaam", -6.79, 39.21, ["dar es salaam", "tanzania"]),
            entry("Tunis", "突尼斯", "TN", "🇹🇳", "Africa/Tunis", 36.81, 10.18, ["tunis", "tunisia"]),
            entry("Algiers", "阿尔及尔", "DZ", "🇩🇿", "Africa/Algiers", 36.75, 3.06, ["algiers", "algeria"]),

            // —— 北美 ——
            entry("New York", "纽约", "US", "🇺🇸", "America/New_York", 40.71, -74.01, ["new york", "nyc", "est", "edt", "纽约"]),
            entry("Boston", "波士顿", "US", "🇺🇸", "America/New_York", 42.36, -71.06, ["boston"]),
            entry("Washington, D.C.", "华盛顿", "US", "🇺🇸", "America/New_York", 38.91, -77.04, ["washington", "dc", "d.c."]),
            entry("Philadelphia", "费城", "US", "🇺🇸", "America/New_York", 39.95, -75.17, ["philadelphia", "philly"]),
            entry("Miami", "迈阿密", "US", "🇺🇸", "America/New_York", 25.76, -80.19, ["miami"]),
            entry("Atlanta", "亚特兰大", "US", "🇺🇸", "America/New_York", 33.75, -84.39, ["atlanta"]),
            entry("Charlotte", "夏洛特", "US", "🇺🇸", "America/New_York", 35.23, -80.84, ["charlotte"]),
            entry("Chicago", "芝加哥", "US", "🇺🇸", "America/Chicago", 41.88, -87.63, ["chicago", "cst", "cdt"]),
            entry("Dallas", "达拉斯", "US", "🇺🇸", "America/Chicago", 32.78, -96.80, ["dallas"]),
            entry("Houston", "休斯顿", "US", "🇺🇸", "America/Chicago", 29.76, -95.37, ["houston"]),
            entry("Austin", "奥斯汀", "US", "🇺🇸", "America/Chicago", 30.27, -97.74, ["austin"]),
            entry("Minneapolis", "明尼阿波利斯", "US", "🇺🇸", "America/Chicago", 44.98, -93.27, ["minneapolis"]),
            entry("Denver", "丹佛", "US", "🇺🇸", "America/Denver", 39.74, -104.99, ["denver", "mst", "mdt"]),
            entry("Salt Lake City", "盐湖城", "US", "🇺🇸", "America/Denver", 40.76, -111.89, ["salt lake", "slc"]),
            entry("Phoenix", "凤凰城", "US", "🇺🇸", "America/Phoenix", 33.45, -112.07, ["phoenix", "arizona"]),
            entry("Los Angeles", "洛杉矶", "US", "🇺🇸", "America/Los_Angeles", 34.05, -118.24, ["los angeles", "la", "pst", "pdt"]),
            entry("San Francisco", "旧金山", "US", "🇺🇸", "America/Los_Angeles", 37.77, -122.42, ["san francisco", "sf", "silicon", "硅谷", "三藩市"]),
            entry("San Diego", "圣地亚哥", "US", "🇺🇸", "America/Los_Angeles", 32.72, -117.16, ["san diego"]),
            entry("San Jose", "圣何塞", "US", "🇺🇸", "America/Los_Angeles", 37.34, -121.89, ["san jose", "sanjose"]),
            entry("Seattle", "西雅图", "US", "🇺🇸", "America/Los_Angeles", 47.61, -122.33, ["seattle"]),
            entry("Portland", "波特兰", "Oregon, US", "🇺🇸", "America/Los_Angeles", 45.52, -122.68, ["portland", "oregon", "pdx"]),
            entry("Portland", "波特兰", "Maine, US", "🇺🇸", "America/New_York", 43.66, -70.26, ["portland", "maine"]),
            entry("Las Vegas", "拉斯维加斯", "US", "🇺🇸", "America/Los_Angeles", 36.17, -115.14, ["las vegas", "vegas"]),
            entry("Honolulu", "檀香山", "US", "🇺🇸", "Pacific/Honolulu", 21.31, -157.86, ["honolulu", "hawaii", "hst", "夏威夷"]),
            entry("Anchorage", "安克雷奇", "US", "🇺🇸", "America/Anchorage", 61.22, -149.90, ["anchorage", "alaska", "akst", "阿拉斯加"]),
            entry("Toronto", "多伦多", "CA", "🇨🇦", "America/Toronto", 43.65, -79.38, ["toronto", "canada", "加拿大"]),
            entry("Montreal", "蒙特利尔", "CA", "🇨🇦", "America/Toronto", 45.50, -73.57, ["montreal", "montréal"]),
            entry("Ottawa", "渥太华", "CA", "🇨🇦", "America/Toronto", 45.42, -75.70, ["ottawa"]),
            entry("Vancouver", "温哥华", "CA", "🇨🇦", "America/Vancouver", 49.28, -123.12, ["vancouver"]),
            entry("Calgary", "卡尔加里", "CA", "🇨🇦", "America/Edmonton", 51.05, -114.07, ["calgary"]),
            entry("Edmonton", "埃德蒙顿", "CA", "🇨🇦", "America/Edmonton", 53.55, -113.49, ["edmonton"]),
            entry("Mexico City", "墨西哥城", "MX", "🇲🇽", "America/Mexico_City", 19.43, -99.13, ["mexico city", "mexico", "墨西哥"]),
            entry("Guadalajara", "瓜达拉哈拉", "MX", "🇲🇽", "America/Mexico_City", 20.66, -103.35, ["guadalajara"]),
            entry("Monterrey", "蒙特雷", "MX", "🇲🇽", "America/Monterrey", 25.69, -100.32, ["monterrey"]),
            entry("Cancún", "坎昆", "MX", "🇲🇽", "America/Cancun", 21.16, -86.85, ["cancun", "cancún"]),

            // —— 中南美 ——
            entry("São Paulo", "圣保罗", "BR", "🇧🇷", "America/Sao_Paulo", -23.55, -46.63, ["sao paulo", "são paulo", "brazil", "巴西"]),
            entry("Rio de Janeiro", "里约热内卢", "BR", "🇧🇷", "America/Sao_Paulo", -22.91, -43.17, ["rio", "rio de janeiro", "里约"]),
            entry("Brasília", "巴西利亚", "BR", "🇧🇷", "America/Sao_Paulo", -15.79, -47.88, ["brasilia", "brasília"]),
            entry("Buenos Aires", "布宜诺斯艾利斯", "AR", "🇦🇷", "America/Argentina/Buenos_Aires", -34.60, -58.38, ["buenos aires", "argentina", "阿根廷"]),
            entry("Santiago", "圣地亚哥", "CL", "🇨🇱", "America/Santiago", -33.45, -70.67, ["santiago", "chile", "智利"]),
            entry("Lima", "利马", "PE", "🇵🇪", "America/Lima", -12.05, -77.04, ["lima", "peru", "秘鲁"]),
            entry("Bogotá", "波哥大", "CO", "🇨🇴", "America/Bogota", 4.71, -74.07, ["bogota", "bogotá", "colombia", "哥伦比亚"]),
            entry("Caracas", "加拉加斯", "VE", "🇻🇪", "America/Caracas", 10.48, -66.90, ["caracas", "venezuela", "委内瑞拉"]),
            entry("Quito", "基多", "EC", "🇪🇨", "America/Guayaquil", -0.18, -78.47, ["quito", "ecuador", "厄瓜多尔"]),
            entry("Montevideo", "蒙得维的亚", "UY", "🇺🇾", "America/Montevideo", -34.90, -56.19, ["montevideo", "uruguay"]),
            entry("Havana", "哈瓦那", "CU", "🇨🇺", "America/Havana", 23.11, -82.37, ["havana", "cuba", "古巴"]),
            entry("Panama City", "巴拿马城", "PA", "🇵🇦", "America/Panama", 8.98, -79.52, ["panama", "巴拿马"]),
            entry("San José", "圣何塞", "CR", "🇨🇷", "America/Costa_Rica", 9.93, -84.09, ["san jose", "costa rica", "哥斯达黎加"]),

            // —— 大洋洲 ——
            entry("Sydney", "悉尼", "AU", "🇦🇺", "Australia/Sydney", -33.87, 151.21, ["sydney", "aest", "aedt", "澳洲", "australia"]),
            entry("Melbourne", "墨尔本", "AU", "🇦🇺", "Australia/Melbourne", -37.81, 144.96, ["melbourne"]),
            entry("Brisbane", "布里斯班", "AU", "🇦🇺", "Australia/Brisbane", -27.47, 153.03, ["brisbane"]),
            entry("Perth", "珀斯", "AU", "🇦🇺", "Australia/Perth", -31.95, 115.86, ["perth", "awst"]),
            entry("Adelaide", "阿德莱德", "AU", "🇦🇺", "Australia/Adelaide", -34.93, 138.60, ["adelaide"]),
            entry("Canberra", "堪培拉", "AU", "🇦🇺", "Australia/Sydney", -35.28, 149.13, ["canberra"]),
            entry("Gold Coast", "黄金海岸", "AU", "🇦🇺", "Australia/Brisbane", -28.02, 153.40, ["gold coast"]),
            entry("Auckland", "奥克兰", "NZ", "🇳🇿", "Pacific/Auckland", -36.85, 174.76, ["auckland", "nzst", "nzdt", "新西兰"]),
            entry("Wellington", "惠灵顿", "NZ", "🇳🇿", "Pacific/Auckland", -41.29, 174.78, ["wellington"]),
            entry("Christchurch", "基督城", "NZ", "🇳🇿", "Pacific/Auckland", -43.53, 172.64, ["christchurch"]),
            entry("Suva", "苏瓦", "FJ", "🇫🇯", "Pacific/Fiji", -18.14, 178.44, ["suva", "fiji", "斐济"]),
            entry("Nouméa", "努美阿", "NC", "🇳🇨", "Pacific/Noumea", -22.28, 166.46, ["noumea", "nouméa", "new caledonia"]),
            entry("Papeete", "帕皮提", "PF", "🇵🇫", "Pacific/Tahiti", -17.56, -149.57, ["papeete", "tahiti", "大溪地"]),
            entry("Guam", "关岛", "GU", "🇬🇺", "Pacific/Guam", 13.44, 144.79, ["guam", "关岛"]),
        ]
    }
}
