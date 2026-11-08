import Foundation

/// 固钉标的（持久化）。
struct StockPin: Identifiable, Codable, Equatable, Hashable {
    var id: String { symbol }
    /// Yahoo 代码，如 `AAPL` / `0700.HK` / `600519.SS`。
    var symbol: String
    /// 展示用中文或简称；空则用行情短名。
    var displayName: String
}

enum StockColorConvention: String, Codable, CaseIterable {
    /// 绿涨红跌。
    case international
    /// 红涨绿跌。
    case greaterChina
}

enum StockPriceFormat: String, Codable, CaseIterable {
    /// `$232.85` / `HK$…` / `¥…`
    case adaptiveCurrency
    /// 纯数值。
    case bareNumber
    /// 涨跌幅优先（大号百分比）。
    case percentPriority
}

/// 实际命中的行情源（随连通情况自动切换）。
enum StockQuoteProvider: String, Codable, CaseIterable, Equatable {
    case yahooChart = "yahoo.chart"
    case yahooQuote = "yahoo.quote"
    case stooq = "stooq"
    case sina = "sina"
    case eastmoney = "eastmoney"

    /// 是否带当日分时波形。
    var providesSparkline: Bool {
        self == .yahooChart
    }
}

/// 单标的实时快照（岛上 / 设置行）；可落盘作离线降级。
struct StockQuoteSnapshot: Identifiable, Equatable, Codable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var exchange: String
    var currency: String
    var price: Double
    var change: Double
    var changePercent: Double
    var dayLow: Double
    var dayHigh: Double
    var postPrice: Double?
    var postChangePercent: Double?
    /// 当日分时收盘序列（用于 sparkline）。
    var sparkline: [Double]
    var marketState: String
    var updatedAt: Date
    var isStale: Bool
    /// 本条价格命中的数据源；缓存恢复时可能为空。
    var provider: StockQuoteProvider?

    var isUp: Bool { change >= 0 }

    enum CodingKeys: String, CodingKey {
        case symbol, name, exchange, currency, price, change, changePercent
        case dayLow, dayHigh, postPrice, postChangePercent, sparkline
        case marketState, updatedAt, isStale, provider
    }
}

struct StockSearchHit: Identifiable, Hashable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var exchange: String
    var quoteType: String
}
