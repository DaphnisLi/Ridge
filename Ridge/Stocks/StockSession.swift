import Combine
import Foundation

/// 股票会话：按间隔拉取 Yahoo 行情；开盘密、休市疏；失败指数退避。
@MainActor
final class StockSession: ObservableObject {
    static let shared = StockSession()

    @Published private(set) var snapshots: [StockQuoteSnapshot] = []
    @Published private(set) var wantsIslandDisplay = false
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private let settings = StockSettings.shared
    private var timer: Timer?
    private var started = false
    private var widgetEnabled = false
    private var settingsObservers: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var nextInterval: TimeInterval = 60
    private var refreshGeneration = 0

    private static let cacheKey = "stocks.session.snapshots.v1"

    private init() {
        let cached = Self.loadCachedSnapshots()
        let pinSymbols = Set(settings.pins.map { $0.symbol.uppercased() })
        snapshots = cached.filter { pinSymbols.contains($0.symbol.uppercased()) }
        if !snapshots.isEmpty {
            AppLog.info("Stocks", "已载入缓存行情", ["count": snapshots.count])
        }
        // 仅固钉列表变化才拉行情；改配色/格式不该打断展示。
        settings.$pins
            .map { $0.map(\.symbol) }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefresh(reason: "pinsChanged", immediate: true)
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
        updateDemand(reason: "enabled")
    }

    func start() {
        guard !started else {
            scheduleRefresh(reason: "resume", immediate: true)
            return
        }
        started = true
        AppLog.warn("Stocks", "股票会话已启动", ["pins": settings.pins.count])
        scheduleRefresh(reason: "start", immediate: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        started = false
        AppLog.warn("Stocks", "股票会话已停止")
    }

    func refresh(reason: String) {
        scheduleRefresh(reason: reason, immediate: true)
    }

    private func scheduleRefresh(reason: String, immediate: Bool) {
        timer?.invalidate()
        timer = nil
        guard widgetEnabled || started else { return }

        if immediate {
            kickRefresh(reason: reason)
        }

        let interval = nextInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.kickRefresh(reason: "timer")
                self.scheduleRefresh(reason: "timerArm", immediate: false)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func kickRefresh(reason: String) {
        let pins = settings.pins
        guard !pins.isEmpty else {
            refreshGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            snapshots = []
            lastError = nil
            isRefreshing = false
            updateDemand(reason: reason)
            return
        }

        // 已在刷且非手动触发：避免连环 cancel 把成功请求掐掉。
        if isRefreshing, reason == "timer" || reason == "timerArm" {
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        isRefreshing = true
        let previous = snapshots

        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == self.refreshGeneration {
                    self.isRefreshing = false
                }
            }

            // 并行拉取，缩短「正在更新」停留时间。
            let results: [(String, Result<StockQuoteSnapshot, Error>)] = await withTaskGroup(
                of: (String, Result<StockQuoteSnapshot, Error>).self
            ) { group in
                for pin in pins {
                    let previousSnap = previous.first {
                        $0.symbol.caseInsensitiveCompare(pin.symbol) == .orderedSame
                    }
                    group.addTask {
                        do {
                            var quote = try await StockQuoteClient.quote(
                                symbol: pin.symbol,
                                previous: previousSnap
                            )
                            let name = pin.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty { quote.name = name }
                            return (pin.symbol, .success(quote))
                        } catch {
                            return (pin.symbol, .failure(error))
                        }
                    }
                }
                var collected: [(String, Result<StockQuoteSnapshot, Error>)] = []
                for await item in group {
                    collected.append(item)
                }
                return collected
            }

            guard !Task.isCancelled, generation == self.refreshGeneration else { return }

            var bySymbol: [String: StockQuoteSnapshot] = [:]
            var failed = 0
            for (symbol, result) in results {
                switch result {
                case .success(let quote):
                    bySymbol[symbol.uppercased()] = quote
                case .failure(let error):
                    let ns = error as NSError
                    if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                        if let old = previous.first(where: {
                            $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame
                        }) {
                            bySymbol[symbol.uppercased()] = old
                        }
                        continue
                    }
                    failed += 1
                    if var old = previous.first(where: {
                        $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame
                    }) {
                        old.isStale = true
                        bySymbol[symbol.uppercased()] = old
                    }
                    AppLog.warn("Stocks", "拉取行情失败", [
                        "symbol": symbol,
                        "reason": reason,
                        "error": String(describing: error)
                    ])
                }
            }

            // 按固钉顺序输出；全失败时保留旧快照，避免整表变「更新中」。
            let ordered = pins.compactMap { bySymbol[$0.symbol.uppercased()] }
            if !ordered.isEmpty {
                self.snapshots = ordered
                Self.persistSnapshots(ordered)
            } else if failed == pins.count, !pins.isEmpty {
                self.snapshots = Self.staleOverlay(previous, keeping: pins)
            }

            if failed == pins.count, !pins.isEmpty {
                self.consecutiveFailures += 1
                self.lastError = L10n.Stocks.fetchFailed
                self.nextInterval = min(300, 60 * pow(2.0, Double(min(self.consecutiveFailures, 3))))
                AppLog.warn("Stocks", "行情全部失败，已退避", [
                    "failures": self.consecutiveFailures,
                    "nextSec": Int(self.nextInterval)
                ])
            } else {
                if failed == 0 {
                    self.consecutiveFailures = 0
                    self.lastError = nil
                } else {
                    self.lastError = L10n.Stocks.fetchPartial
                }
                self.nextInterval = self.preferredInterval(from: self.snapshots)
                let sources = self.snapshots.compactMap { $0.provider?.rawValue }.joined(separator: ",")
                AppLog.info("Stocks", "行情刷新完成", [
                    "reason": reason,
                    "ok": pins.count - failed,
                    "failed": failed,
                    "sources": sources
                ])
            }
            self.updateDemand(reason: reason)
        }
    }

    private static func staleOverlay(
        _ previous: [StockQuoteSnapshot],
        keeping pins: [StockPin]
    ) -> [StockQuoteSnapshot] {
        pins.compactMap { pin in
            guard var old = previous.first(where: {
                $0.symbol.caseInsensitiveCompare(pin.symbol) == .orderedSame
            }) else { return nil }
            old.isStale = true
            return old
        }
    }

    private static func loadCachedSnapshots() -> [StockQuoteSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([StockQuoteSnapshot].self, from: data)
        else { return [] }
        return decoded.map { snap in
            var copy = snap
            copy.isStale = true
            return copy
        }
    }

    private static func persistSnapshots(_ snapshots: [StockQuoteSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        AppLog.debug("Stocks", "已缓存行情快照", ["count": snapshots.count])
    }

    /// 固钉区展示用：汇总当前命中的数据源（随刷新变化）。
    var dataSourceSummaryText: String {
        L10n.Stocks.dataSourceSummary(dataSourceShortName)
    }

    /// 胶囊芯片用：仅来源名（不含「数据源：」前缀）。
    var dataSourceShortName: String {
        let providers = snapshots.compactMap(\.provider)
        if providers.isEmpty {
            if snapshots.contains(where: { $0.isStale }) {
                return L10n.Stocks.dataSourceCached
            }
            return L10n.Stocks.dataSourceUnknown
        }
        let unique = Array(Set(providers)).sorted { $0.rawValue < $1.rawValue }
        if unique.count == 1, let only = unique.first {
            return L10n.Stocks.providerName(only)
        }
        let names = unique.map(L10n.Stocks.providerName).joined(separator: "、")
        return "\(L10n.Stocks.dataSourceMixed)（\(names)）"
    }

    /// 有实时源时为 true（绿点）；仅缓存 / 暂无为 false。
    var dataSourceIsLive: Bool {
        snapshots.contains { $0.provider != nil }
    }

    /// 任一标的处于 REGULAR 则用用户设定间隔；否则 5 分钟。
    private func preferredInterval(from quotes: [StockQuoteSnapshot]) -> TimeInterval {
        let open = quotes.contains {
            let state = $0.marketState.uppercased()
            return state == "REGULAR" || state == "PRE" || state == "POST"
        }
        let base = TimeInterval(max(15, settings.refreshSeconds))
        return open ? base : max(base, 300)
    }

    private func updateDemand(reason: String) {
        let shouldShow = widgetEnabled && !settings.pins.isEmpty
        if shouldShow != wantsIslandDisplay {
            wantsIslandDisplay = shouldShow
            AppLog.warn("Stocks", shouldShow ? "申请上岛" : "撤回上岛", [
                "reason": reason,
                "pins": settings.pins.count
            ])
        }
    }

    // MARK: - Formatting helpers

    static func currencyPrefix(_ currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "HKD": return "HK$"
        case "CNY", "CNH": return "¥"
        case "JPY": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }

    static func formatPrice(_ value: Double, currency: String, format: StockPriceFormat) -> String {
        let number = String(format: abs(value) >= 1000 ? "%.2f" : "%.2f", value)
        switch format {
        case .bareNumber, .percentPriority:
            return number
        case .adaptiveCurrency:
            return currencyPrefix(currency) + number
        }
    }

    static func formatSigned(_ value: Double, digits: Int = 2) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + String(format: "%.\(digits)f", value)
    }

    static func formatPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + String(format: "%.2f%%", value)
    }

    /// 涨为正色、跌为负色（随配色惯例翻转）。
    static func isPositiveTone(isUp: Bool, convention: StockColorConvention) -> Bool {
        switch convention {
        case .international: return isUp
        case .greaterChina: return !isUp
        }
    }
}
