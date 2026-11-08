import Foundation

/// 多源行情：Yahoo → Stooq → 新浪 → 东财；任一成功即返回。
enum StockQuoteClient {
    static func quote(
        symbol: String,
        previous: StockQuoteSnapshot? = nil
    ) async throws -> StockQuoteSnapshot {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty else { throw StockClientError.empty }

        var errors: [String] = []
        let providers: [(String, () async throws -> StockQuoteSnapshot)] = [
            ("yahoo.chart", { try await StockYahooClient.chart(symbol: symbol) }),
            ("yahoo.quote", { try await yahooQuote(symbol: symbol) }),
            ("stooq", { try await stooqQuote(symbol: symbol) }),
            ("sina", { try await sinaQuote(symbol: symbol) }),
            ("eastmoney", { try await eastmoneyQuote(symbol: symbol) }),
        ]

        for (name, fetch) in providers {
            do {
                var snap = try await fetch()
                snap.provider = StockQuoteProvider(rawValue: name)
                if snap.sparkline.isEmpty, let previous, !previous.sparkline.isEmpty {
                    snap.sparkline = previous.sparkline
                }
                if snap.name.isEmpty || snap.name == snap.symbol, let previous, !previous.name.isEmpty {
                    snap.name = previous.name
                }
                AppLog.info("Stocks", "行情源命中", ["symbol": symbol, "provider": name])
                return snap
            } catch {
                errors.append("\(name):\((error as NSError).code)")
                AppLog.debug("Stocks", "行情源失败", [
                    "symbol": symbol,
                    "provider": name,
                    "error": String(describing: error)
                ])
            }
        }

        AppLog.warn("Stocks", "全部行情源失败", [
            "symbol": symbol,
            "tried": errors.joined(separator: ",")
        ])
        throw StockClientError.empty
    }

    // MARK: - Yahoo quote (无分时，作 chart 备用)

    private static func yahooQuote(symbol: String) async throws -> StockQuoteSnapshot {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let hosts = [
            "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(encoded)",
            "https://query2.finance.yahoo.com/v7/finance/quote?symbols=\(encoded)",
        ]
        var lastError: Error = StockClientError.empty
        for host in hosts {
            guard let url = URL(string: host) else { continue }
            do {
                let (data, _) = try await StockNetwork.data(from: url)
                let decoded = try JSONDecoder().decode(YahooQuoteEnvelope.self, from: data)
                guard let q = decoded.quoteResponse?.result?.first else { throw StockClientError.empty }
                let price = q.regularMarketPrice ?? q.postMarketPrice ?? q.preMarketPrice ?? 0
                let previous = q.regularMarketPreviousClose ?? price
                let change = q.regularMarketChange ?? (price - previous)
                let pct = q.regularMarketChangePercent
                    ?? (previous == 0 ? 0 : (change / previous) * 100)
                return StockQuoteSnapshot(
                    symbol: q.symbol ?? symbol,
                    name: q.shortName ?? q.longName ?? symbol,
                    exchange: q.fullExchangeName ?? q.exchange ?? "",
                    currency: q.currency ?? "USD",
                    price: price,
                    change: change,
                    changePercent: pct,
                    dayLow: q.regularMarketDayLow ?? price,
                    dayHigh: q.regularMarketDayHigh ?? price,
                    postPrice: q.postMarketPrice ?? q.preMarketPrice,
                    postChangePercent: q.postMarketChangePercent ?? q.preMarketChangePercent,
                    sparkline: [],
                    marketState: q.marketState ?? "",
                    updatedAt: Date(),
                    isStale: false,
                    provider: .yahooQuote
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Stooq CSV

    private static func stooqQuote(symbol: String) async throws -> StockQuoteSnapshot {
        guard let stooq = StockSymbolMap.stooq(symbol) else { throw StockClientError.unsupported }
        var components = URLComponents(string: "https://stooq.com/q/l/")!
        components.queryItems = [
            URLQueryItem(name: "s", value: stooq),
            URLQueryItem(name: "f", value: "sd2t2ohlcv"),
            URLQueryItem(name: "h", value: ""),
            URLQueryItem(name: "e", value: "csv"),
        ]
        guard let url = components.url else { throw StockClientError.empty }
        let (data, _) = try await StockNetwork.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else { throw StockClientError.empty }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else { throw StockClientError.empty }
        let cols = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        // Symbol,Date,Time,Open,High,Low,Close,Volume
        guard cols.count >= 7, let close = Double(cols[6]), close > 0 else { throw StockClientError.empty }
        let open = Double(cols[3]) ?? close
        let high = Double(cols[4]) ?? close
        let low = Double(cols[5]) ?? close
        let change = close - open
        let pct = open == 0 ? 0 : (change / open) * 100
        return StockQuoteSnapshot(
            symbol: symbol.uppercased(),
            name: symbol.uppercased(),
            exchange: StockSymbolMap.exchangeHint(symbol),
            currency: StockSymbolMap.currencyHint(symbol),
            price: close,
            change: change,
            changePercent: pct,
            dayLow: low,
            dayHigh: high,
            postPrice: nil,
            postChangePercent: nil,
            sparkline: [],
            marketState: "",
            updatedAt: Date(),
            isStale: false,
            provider: .stooq
        )
    }

    // MARK: - 新浪

    private static func sinaQuote(symbol: String) async throws -> StockQuoteSnapshot {
        guard let sina = StockSymbolMap.sina(symbol) else { throw StockClientError.unsupported }
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(sina)") else { throw StockClientError.empty }
        let (data, _) = try await StockNetwork.data(
            from: url,
            extraHeaders: ["Referer": "https://finance.sina.com.cn"]
        )
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        // var hq_str_xxx="a,b,c,...";
        guard let start = text.firstIndex(of: "\""),
              let end = text[text.index(after: start)...].firstIndex(of: "\"")
        else { throw StockClientError.empty }
        let payload = String(text[text.index(after: start)..<end])
        let parts = payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { throw StockClientError.empty }

        if sina.hasPrefix("gb_") {
            // name,price,change%,date,time,change,open,high,low,...
            guard parts.count >= 9,
                  let price = Double(parts[1]), price > 0
            else { throw StockClientError.empty }
            let change = Double(parts[5]) ?? 0
            let pct = Double(parts[2]) ?? 0
            let open = Double(parts[6]) ?? price
            let high = Double(parts[7]) ?? price
            let low = Double(parts[8]) ?? price
            return StockQuoteSnapshot(
                symbol: symbol.uppercased(),
                name: parts[0].isEmpty ? symbol.uppercased() : parts[0],
                exchange: "NMS",
                currency: "USD",
                price: price,
                change: change,
                changePercent: pct,
                dayLow: low,
                dayHigh: high,
                postPrice: nil,
                postChangePercent: nil,
                sparkline: [],
                marketState: "",
                updatedAt: Date(),
                isStale: false,
                provider: .sina
            )
        }

        if sina.hasPrefix("rt_hk") {
            // name, open?, ..., price around index 6 for HK — use common layout:
            // 0 name, 2 prev, 6 price (varies). Prefer known: index 6 last price for rt_hk.
            guard parts.count > 12,
                  let price = Double(parts[6]), price > 0,
                  let previous = Double(parts[3]), previous > 0
            else { throw StockClientError.empty }
            let change = price - previous
            let pct = (change / previous) * 100
            let high = Double(parts[4]) ?? price
            let low = Double(parts[5]) ?? price
            return StockQuoteSnapshot(
                symbol: symbol.uppercased(),
                name: parts[0].isEmpty ? symbol.uppercased() : parts[0],
                exchange: "HKG",
                currency: "HKD",
                price: price,
                change: change,
                changePercent: pct,
                dayLow: low,
                dayHigh: high,
                postPrice: nil,
                postChangePercent: nil,
                sparkline: [],
                marketState: "",
                updatedAt: Date(),
                isStale: false,
                provider: .sina
            )
        }

        // A 股 sh/sz：0 name,1 open,2 prev,3 price,4 high,5 low
        guard parts.count > 5,
              let price = Double(parts[3]), price > 0,
              let previous = Double(parts[2]), previous > 0
        else { throw StockClientError.empty }
        let change = price - previous
        let pct = (change / previous) * 100
        return StockQuoteSnapshot(
            symbol: symbol.uppercased(),
            name: parts[0].isEmpty ? symbol.uppercased() : parts[0],
            exchange: sina.hasPrefix("sh") ? "SHH" : "SHZ",
            currency: "CNY",
            price: price,
            change: change,
            changePercent: pct,
            dayLow: Double(parts[5]) ?? price,
            dayHigh: Double(parts[4]) ?? price,
            postPrice: nil,
            postChangePercent: nil,
            sparkline: [],
            marketState: "",
            updatedAt: Date(),
            isStale: false,
            provider: .sina
        )
    }

    // MARK: - 东财

    private static func eastmoneyQuote(symbol: String) async throws -> StockQuoteSnapshot {
        guard let secid = StockSymbolMap.eastmoneySecid(symbol) else { throw StockClientError.unsupported }
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/stock/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: secid),
            URLQueryItem(name: "fields", value: "f43,f44,f45,f46,f57,f58,f60,f169,f170,f152"),
        ]
        guard let url = components.url else { throw StockClientError.empty }
        let (data, _) = try await StockNetwork.data(from: url)
        let decoded = try JSONDecoder().decode(EastMoneyEnvelope.self, from: data)
        guard let d = decoded.data else { throw StockClientError.empty }
        let scale = pow(10.0, Double(d.f152 ?? 2))
        guard let rawPrice = d.f43, rawPrice != 0 else { throw StockClientError.empty }
        let price = Double(rawPrice) / scale
        let previous = Double(d.f60 ?? rawPrice) / scale
        let change = Double(d.f169 ?? 0) / scale
        let pct = Double(d.f170 ?? 0) / 100.0
        let high = Double(d.f44 ?? rawPrice) / scale
        let low = Double(d.f45 ?? rawPrice) / scale
        return StockQuoteSnapshot(
            symbol: symbol.uppercased(),
            name: d.f58 ?? symbol.uppercased(),
            exchange: StockSymbolMap.exchangeHint(symbol),
            currency: StockSymbolMap.currencyHint(symbol),
            price: price,
            change: change == 0 ? (price - previous) : change,
            changePercent: pct,
            dayLow: low,
            dayHigh: high,
            postPrice: nil,
            postChangePercent: nil,
            sparkline: [],
            marketState: "",
            updatedAt: Date(),
            isStale: false,
            provider: .eastmoney
        )
    }
}

// MARK: - Symbol map

enum StockSymbolMap {
    static func stooq(_ yahoo: String) -> String? {
        let s = yahoo.uppercased()
        if s.hasSuffix(".HK") {
            return String(s.dropLast(3)).lowercased() + ".hk"
        }
        if s.hasSuffix(".SS") || s.hasSuffix(".SZ") {
            return String(s.dropLast(3)).lowercased() + ".cn"
        }
        if s.contains(".") { return nil }
        return s.lowercased() + ".us"
    }

    static func sina(_ yahoo: String) -> String? {
        let s = yahoo.uppercased()
        if s.hasSuffix(".HK") {
            let code = String(s.dropLast(3))
            let padded = String(repeating: "0", count: max(0, 5 - code.count)) + code
            return "rt_hk" + padded
        }
        if s.hasSuffix(".SS") { return "sh" + String(s.dropLast(3)) }
        if s.hasSuffix(".SZ") { return "sz" + String(s.dropLast(3)) }
        if s.contains(".") { return nil }
        return "gb_" + s.lowercased()
    }

    static func eastmoneySecid(_ yahoo: String) -> String? {
        let s = yahoo.uppercased()
        if s.hasSuffix(".HK") {
            let code = String(s.dropLast(3))
            let padded = String(repeating: "0", count: max(0, 5 - code.count)) + code
            return "116." + padded
        }
        if s.hasSuffix(".SS") { return "1." + String(s.dropLast(3)) }
        if s.hasSuffix(".SZ") { return "0." + String(s.dropLast(3)) }
        if s.contains(".") { return nil }
        return "105." + s
    }

    static func exchangeHint(_ yahoo: String) -> String {
        let s = yahoo.uppercased()
        if s.hasSuffix(".HK") { return "HKG" }
        if s.hasSuffix(".SS") { return "SHH" }
        if s.hasSuffix(".SZ") { return "SHZ" }
        return "NMS"
    }

    static func currencyHint(_ yahoo: String) -> String {
        let s = yahoo.uppercased()
        if s.hasSuffix(".HK") { return "HKD" }
        if s.hasSuffix(".SS") || s.hasSuffix(".SZ") { return "CNY" }
        return "USD"
    }
}

// MARK: - Decode

private struct YahooQuoteEnvelope: Decodable {
    var quoteResponse: YahooQuoteResponse?
}

private struct YahooQuoteResponse: Decodable {
    var result: [YahooQuoteItem]?
}

private struct YahooQuoteItem: Decodable {
    var symbol: String?
    var shortName: String?
    var longName: String?
    var exchange: String?
    var fullExchangeName: String?
    var currency: String?
    var marketState: String?
    var regularMarketPrice: Double?
    var regularMarketChange: Double?
    var regularMarketChangePercent: Double?
    var regularMarketPreviousClose: Double?
    var regularMarketDayHigh: Double?
    var regularMarketDayLow: Double?
    var postMarketPrice: Double?
    var postMarketChangePercent: Double?
    var preMarketPrice: Double?
    var preMarketChangePercent: Double?
}

private struct EastMoneyEnvelope: Decodable {
    var data: EastMoneyData?
}

private struct EastMoneyData: Decodable {
    var f43: Int?
    var f44: Int?
    var f45: Int?
    var f46: Int?
    var f57: String?
    var f58: String?
    var f60: Int?
    var f169: Int?
    var f170: Int?
    var f152: Int?
}
