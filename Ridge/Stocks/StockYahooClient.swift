import Foundation

/// Yahoo Finance 公开接口：搜索 + 当日分时图（含现价 / 涨跌 / 盘后）。
/// 网络走 `StockNetwork`（代理失败自动直连）；完整多源见 `StockQuoteClient`。
enum StockYahooClient {
    /// 支持代码与英文名；中文名经本地别名映射后再查 Yahoo。
    static func search(query: String, limit: Int = 8) async throws -> [StockSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let local = StockSearchIndex.localHits(for: q, limit: limit)
        var merged: [StockSearchHit] = local
        var seen = Set(local.map { $0.symbol.uppercased() })

        let candidates = StockSearchIndex.queryCandidates(for: q)
        for candidate in candidates.prefix(3) {
            // 纯中文且与候选相同、又不是 ASCII 代码时，Yahoo 常直接 Bad Request，跳过。
            if looksLikeCJKOnly(candidate), candidate == q { continue }
            do {
                let remote = try await searchRemote(query: candidate, limit: limit)
                for hit in remote {
                    let key = hit.symbol.uppercased()
                    guard seen.insert(key).inserted else { continue }
                    merged.append(hit)
                }
            } catch {
                AppLog.debug("Stocks", "远程搜索候选失败", [
                    "q": candidate,
                    "error": String(describing: error)
                ])
            }
            if merged.count >= limit { break }
        }

        // 股票优先于期货 / 期权噪声。
        merged.sort { lhs, rhs in
            let lEquity = lhs.quoteType.uppercased() == "EQUITY" ? 0 : 1
            let rEquity = rhs.quoteType.uppercased() == "EQUITY" ? 0 : 1
            if lEquity != rEquity { return lEquity < rEquity }
            return lhs.symbol < rhs.symbol
        }
        return Array(merged.prefix(limit))
    }

    private static func searchRemote(query: String, limit: Int) async throws -> [StockSearchHit] {
        let hosts = [
            "https://query1.finance.yahoo.com/v1/finance/search",
            "https://query2.finance.yahoo.com/v1/finance/search",
        ]
        var lastError: Error = StockClientError.empty
        for host in hosts {
            var components = URLComponents(string: host)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "quotesCount", value: "\(limit)"),
                URLQueryItem(name: "newsCount", value: "0"),
                URLQueryItem(name: "listsCount", value: "0"),
                URLQueryItem(name: "enableFuzzyQuery", value: "false"),
                URLQueryItem(name: "quotesQueryId", value: "tss_match_phrase_query"),
            ]
            guard let url = components.url else { continue }
            do {
                let (data, _) = try await StockNetwork.data(from: url)
                if let err = try? JSONDecoder().decode(FinanceErrorEnvelope.self, from: data),
                   err.finance?.error != nil
                {
                    throw StockClientError.badQuery
                }
                let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
                return (decoded.quotes ?? []).compactMap { quote in
                    guard let symbol = quote.symbol, !symbol.isEmpty else { return nil }
                    let name = quote.shortname ?? quote.longname ?? symbol
                    return StockSearchHit(
                        symbol: symbol,
                        name: name,
                        exchange: quote.exchDisp ?? quote.exchange ?? "",
                        quoteType: quote.quoteType ?? ""
                    )
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func chart(symbol: String) async throws -> StockQuoteSnapshot {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let hosts = [
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)",
            "https://query2.finance.yahoo.com/v8/finance/chart/\(encoded)",
        ]
        var lastError: Error = StockClientError.empty
        for host in hosts {
            var components = URLComponents(string: host)!
            components.queryItems = [
                URLQueryItem(name: "interval", value: "5m"),
                URLQueryItem(name: "range", value: "1d"),
                URLQueryItem(name: "includePrePost", value: "true"),
            ]
            guard let url = components.url else { continue }
            do {
                let (data, _) = try await StockNetwork.data(from: url)
                let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
                guard let result = decoded.chart?.result?.first,
                      let meta = result.meta
                else { throw StockClientError.empty }

                let closes = result.indicators?.quote?.first?.close ?? []
                let spark = closes.compactMap { $0 }.filter { $0 > 0 }

                let price = meta.regularMarketPrice
                    ?? spark.last
                    ?? meta.previousClose
                    ?? 0
                let previous = meta.chartPreviousClose ?? meta.previousClose ?? price
                let change = price - previous
                let pct = previous == 0 ? 0 : (change / previous) * 100

                var postPrice = meta.postMarketPrice
                var postPct = meta.postMarketChangePercent
                if postPrice == nil, let pre = meta.preMarketPrice {
                    postPrice = pre
                    postPct = meta.preMarketChangePercent
                }

                let name = meta.shortName ?? meta.symbol ?? symbol
                return StockQuoteSnapshot(
                    symbol: meta.symbol ?? symbol,
                    name: name,
                    exchange: meta.exchangeName ?? meta.fullExchangeName ?? "",
                    currency: meta.currency ?? "USD",
                    price: price,
                    change: change,
                    changePercent: pct,
                    dayLow: meta.regularMarketDayLow ?? spark.min() ?? price,
                    dayHigh: meta.regularMarketDayHigh ?? spark.max() ?? price,
                    postPrice: postPrice,
                    postChangePercent: postPct,
                    sparkline: spark,
                    marketState: meta.marketState ?? "",
                    updatedAt: Date(),
                    isStale: false,
                    provider: .yahooChart
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func looksLikeCJKOnly(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        return scalars.allSatisfy { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }
}

enum StockClientError: Error {
    case empty
    case http(Int)
    case badQuery
    case unsupported
}

// MARK: - Decode

private struct SearchResponse: Decodable {
    var quotes: [SearchQuote]?
}

private struct SearchQuote: Decodable {
    var symbol: String?
    var shortname: String?
    var longname: String?
    var exchange: String?
    var exchDisp: String?
    var quoteType: String?
}

private struct FinanceErrorEnvelope: Decodable {
    var finance: FinanceErrorBody?
}

private struct FinanceErrorBody: Decodable {
    var error: FinanceErrorDetail?
}

private struct FinanceErrorDetail: Decodable {
    var code: String?
    var description: String?
}

private struct ChartResponse: Decodable {
    var chart: ChartBody?
}

private struct ChartBody: Decodable {
    var result: [ChartResult]?
}

private struct ChartResult: Decodable {
    var meta: ChartMeta?
    var indicators: ChartIndicators?
}

private struct ChartMeta: Decodable {
    var currency: String?
    var symbol: String?
    var exchangeName: String?
    var fullExchangeName: String?
    var shortName: String?
    var regularMarketPrice: Double?
    var previousClose: Double?
    var chartPreviousClose: Double?
    var regularMarketDayHigh: Double?
    var regularMarketDayLow: Double?
    var postMarketPrice: Double?
    var postMarketChangePercent: Double?
    var preMarketPrice: Double?
    var preMarketChangePercent: Double?
    var marketState: String?
}

private struct ChartIndicators: Decodable {
    var quote: [ChartQuote]?
}

private struct ChartQuote: Decodable {
    var close: [Double?]?
}
