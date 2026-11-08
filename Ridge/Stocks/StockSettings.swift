import Combine
import Foundation

/// 股票小组件偏好与固钉席位。
@MainActor
final class StockSettings: ObservableObject {
    static let shared = StockSettings()

    static let maxPins = 3

    private enum Key {
        static let pins = "stocks.pins.v1"
        static let color = "stocks.colorConvention.v1"
        static let priceFormat = "stocks.priceFormat.v1"
        static let sparkline = "stocks.showSparkline.v1"
        static let refreshSeconds = "stocks.refreshSeconds.v1"
    }

    private let defaults = UserDefaults.standard

    @Published var pins: [StockPin] = [] {
        didSet { persistPins() }
    }

    @Published var colorConvention: StockColorConvention = .international {
        didSet { defaults.set(colorConvention.rawValue, forKey: Key.color) }
    }

    @Published var priceFormat: StockPriceFormat = .adaptiveCurrency {
        didSet { defaults.set(priceFormat.rawValue, forKey: Key.priceFormat) }
    }

    @Published var showSparkline: Bool = true {
        didSet { defaults.set(showSparkline, forKey: Key.sparkline) }
    }

    /// 开盘刷新秒数（休市由 Session 自动拉长）。
    @Published var refreshSeconds: Int = 60 {
        didSet { defaults.set(refreshSeconds, forKey: Key.refreshSeconds) }
    }

    private init() {
        if let data = defaults.data(forKey: Key.pins),
           let decoded = try? JSONDecoder().decode([StockPin].self, from: data),
           !decoded.isEmpty
        {
            pins = Array(decoded.prefix(Self.maxPins))
        } else {
            pins = Self.defaultPins()
            AppLog.info("Stocks", "使用默认自选", ["count": pins.count])
        }

        if let raw = defaults.string(forKey: Key.color),
           let value = StockColorConvention(rawValue: raw)
        {
            colorConvention = value
        }
        if let raw = defaults.string(forKey: Key.priceFormat),
           let value = StockPriceFormat(rawValue: raw)
        {
            priceFormat = value
        }
        if defaults.object(forKey: Key.sparkline) != nil {
            showSparkline = defaults.bool(forKey: Key.sparkline)
        }
        let savedRefresh = defaults.integer(forKey: Key.refreshSeconds)
        if savedRefresh >= 15 {
            refreshSeconds = min(max(savedRefresh, 15), 300)
        }
    }

    var isFull: Bool { pins.count >= Self.maxPins }

    func restoreDefaults() {
        pins = Self.defaultPins()
        colorConvention = .international
        priceFormat = .adaptiveCurrency
        showSparkline = true
        refreshSeconds = 60
        AppLog.info("Stocks", "已恢复默认设置", ["pins": pins.count])
    }

    @discardableResult
    func addPin(_ pin: StockPin) -> Bool {
        let symbol = pin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return false }
        guard !isFull else {
            AppLog.warn("Stocks", "固钉席位已满", ["max": Self.maxPins])
            return false
        }
        if pins.contains(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }) {
            AppLog.info("Stocks", "标的已在自选", ["symbol": symbol])
            return false
        }
        pins.append(StockPin(symbol: symbol, displayName: pin.displayName))
        AppLog.info("Stocks", "已添加标的", ["symbol": symbol, "count": pins.count])
        return true
    }

    func removePin(symbol: String) {
        pins.removeAll { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
        AppLog.info("Stocks", "已移除标的", ["symbol": symbol, "count": pins.count])
    }

    func movePins(from source: IndexSet, to destination: Int) {
        pins.move(fromOffsets: source, toOffset: destination)
        AppLog.info("Stocks", "已调整自选顺序", [
            "from": source.map(String.init).joined(separator: ","),
            "to": destination,
            "count": pins.count
        ])
    }

    private func persistPins() {
        if let data = try? JSONEncoder().encode(pins) {
            defaults.set(data, forKey: Key.pins)
        }
    }

    private static func defaultPins() -> [StockPin] {
        [
            StockPin(symbol: "AAPL", displayName: "苹果公司"),
            StockPin(symbol: "NVDA", displayName: "英伟达"),
            StockPin(symbol: "TSLA", displayName: "特斯拉"),
        ]
    }
}
