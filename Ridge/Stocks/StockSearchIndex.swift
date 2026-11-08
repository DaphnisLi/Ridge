import Foundation

/// 本地名称 / 别名索引：Yahoo 对中文查询常直接拒，先映射成代码或英文名再搜。
enum StockSearchIndex {
    struct Alias {
        var symbol: String
        var nameEN: String
        var nameZH: String
        var keywords: [String]
    }

    static let aliases: [Alias] = [
        Alias(symbol: "AAPL", nameEN: "Apple", nameZH: "苹果", keywords: ["苹果公司", "apple inc"]),
        Alias(symbol: "MSFT", nameEN: "Microsoft", nameZH: "微软", keywords: []),
        Alias(symbol: "GOOGL", nameEN: "Alphabet", nameZH: "谷歌", keywords: ["google", "谷歌", "字母表"]),
        Alias(symbol: "GOOG", nameEN: "Alphabet", nameZH: "谷歌", keywords: ["google"]),
        Alias(symbol: "AMZN", nameEN: "Amazon", nameZH: "亚马逊", keywords: []),
        Alias(symbol: "META", nameEN: "Meta", nameZH: "脸书", keywords: ["facebook", "meta", "元"]),
        Alias(symbol: "NVDA", nameEN: "NVIDIA", nameZH: "英伟达", keywords: ["nvdia", "nvidia"]),
        Alias(symbol: "TSLA", nameEN: "Tesla", nameZH: "特斯拉", keywords: []),
        Alias(symbol: "NFLX", nameEN: "Netflix", nameZH: "奈飞", keywords: ["网飞"]),
        Alias(symbol: "AMD", nameEN: "AMD", nameZH: "超威", keywords: ["超微"]),
        Alias(symbol: "INTC", nameEN: "Intel", nameZH: "英特尔", keywords: []),
        Alias(symbol: "BABA", nameEN: "Alibaba", nameZH: "阿里巴巴", keywords: ["阿里", "alibaba"]),
        Alias(symbol: "JD", nameEN: "JD.com", nameZH: "京东", keywords: []),
        Alias(symbol: "PDD", nameEN: "PDD Holdings", nameZH: "拼多多", keywords: ["pdd"]),
        Alias(symbol: "BIDU", nameEN: "Baidu", nameZH: "百度", keywords: []),
        Alias(symbol: "NIO", nameEN: "NIO", nameZH: "蔚来", keywords: []),
        Alias(symbol: "XPEV", nameEN: "XPeng", nameZH: "小鹏", keywords: ["小鹏汽车"]),
        Alias(symbol: "LI", nameEN: "Li Auto", nameZH: "理想", keywords: ["理想汽车"]),
        Alias(symbol: "0700.HK", nameEN: "Tencent", nameZH: "腾讯", keywords: ["腾讯控股", "tencent"]),
        Alias(symbol: "9988.HK", nameEN: "Alibaba", nameZH: "阿里巴巴", keywords: ["阿里", "baba"]),
        Alias(symbol: "3690.HK", nameEN: "Meituan", nameZH: "美团", keywords: []),
        Alias(symbol: "1810.HK", nameEN: "Xiaomi", nameZH: "小米", keywords: []),
        Alias(symbol: "9618.HK", nameEN: "JD.com", nameZH: "京东", keywords: []),
        Alias(symbol: "9888.HK", nameEN: "Baidu", nameZH: "百度", keywords: []),
        Alias(symbol: "1024.HK", nameEN: "Kuaishou", nameZH: "快手", keywords: []),
        Alias(symbol: "600519.SS", nameEN: "Kweichow Moutai", nameZH: "贵州茅台", keywords: ["茅台", "moutai"]),
        Alias(symbol: "601318.SS", nameEN: "Ping An", nameZH: "中国平安", keywords: ["平安"]),
        Alias(symbol: "600036.SS", nameEN: "China Merchants Bank", nameZH: "招商银行", keywords: ["招行"]),
        Alias(symbol: "000858.SZ", nameEN: "Wuliangye", nameZH: "五粮液", keywords: []),
        Alias(symbol: "300750.SZ", nameEN: "CATL", nameZH: "宁德时代", keywords: ["宁德"]),
        Alias(symbol: "002594.SZ", nameEN: "BYD", nameZH: "比亚迪", keywords: ["byd"]),
        Alias(symbol: "TSM", nameEN: "TSMC", nameZH: "台积电", keywords: ["台积电", "tsmc"]),
        Alias(symbol: "2330.TW", nameEN: "TSMC", nameZH: "台积电", keywords: ["台积电"]),
    ]

    /// 返回应发给 Yahoo 的查询串（原词 + 映射出的英文/代码，去重）。
    static func queryCandidates(for raw: String) -> [String] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        var out: [String] = [q]

        for alias in aliases {
            let pool = ([alias.symbol, alias.nameEN, alias.nameZH] + alias.keywords)
                .map { $0.lowercased() }
            let hit = pool.contains(where: { $0 == lower || $0.hasPrefix(lower) || lower.hasPrefix($0) || $0.contains(lower) })
            guard hit else { continue }
            out.append(alias.symbol)
            out.append(alias.nameEN)
        }
        // 去重保序
        var seen = Set<String>()
        return out.filter { seen.insert($0.lowercased()).inserted }
    }

    /// 纯本地快速命中（输入过程中立刻出列表，不依赖网络）。
    static func localHits(for raw: String, limit: Int = 8) -> [StockSearchHit] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        var scored: [(Int, Alias)] = []
        for alias in aliases {
            let pool = ([alias.symbol, alias.nameEN, alias.nameZH] + alias.keywords).map { $0.lowercased() }
            if pool.contains(where: { $0 == lower }) {
                scored.append((0, alias))
            } else if pool.contains(where: { $0.hasPrefix(lower) }) {
                scored.append((1, alias))
            } else if pool.contains(where: { $0.contains(lower) }) {
                scored.append((2, alias))
            }
        }
        scored.sort { $0.0 < $1.0 }
        return scored.prefix(limit).map { _, alias in
            StockSearchHit(
                symbol: alias.symbol,
                name: alias.nameZH.isEmpty ? alias.nameEN : "\(alias.nameZH)（\(alias.nameEN)）",
                exchange: exchangeHint(for: alias.symbol),
                quoteType: "EQUITY"
            )
        }
    }

    private static func exchangeHint(for symbol: String) -> String {
        if symbol.hasSuffix(".HK") { return "HKEX" }
        if symbol.hasSuffix(".SS") { return "SSE" }
        if symbol.hasSuffix(".SZ") { return "SZSE" }
        if symbol.hasSuffix(".TW") { return "TWSE" }
        return "US"
    }
}
