import SwiftUI

/// 岛上股票三卡（根视图无外圈 padding）。
struct StockIslandView: View {
    @ObservedObject var session: StockSession
    @ObservedObject var settings: StockSettings

    var body: some View {
        let items = displaySnapshots
        Group {
            if items.isEmpty {
                Text(L10n.Stocks.emptyIsland)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.vertical, 10)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(items) { snap in
                        StockIslandCard(
                            snap: snap,
                            settings: settings
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(minWidth: items.isEmpty ? 220 : CGFloat(max(items.count, 1)) * 168)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var displaySnapshots: [StockQuoteSnapshot] {
        session.snapshots
    }

    static func previewSample(compact: Bool = true) -> some View {
        // 预览两卡：单卡约 128，够显示 `$232.85`；比真机 168 窄，避免库卡黑岛过宽。
        StockIslandStaticView(
            snapshots: previewSnapshots(),
            settings: StockSettings.shared,
            cardMinWidth: compact ? 128 : 148,
            compactChrome: compact
        )
    }

    /// 设置 / 库卡预览：两枚假数据样张（涨跌各一），不接实时源。
    static func previewSnapshots() -> [StockQuoteSnapshot] {
        [
            StockQuoteSnapshot(
                symbol: "AAPL",
                name: "苹果公司",
                exchange: "NASDAQ",
                currency: "USD",
                price: 232.85,
                change: 4.20,
                changePercent: 1.84,
                dayLow: 229.4,
                dayHigh: 233.5,
                postPrice: 233.10,
                postChangePercent: 0.11,
                sparkline: [228, 229, 230, 229.5, 231, 230.5, 232, 231.8, 232.85],
                marketState: "POST",
                updatedAt: Date(),
                isStale: false,
                provider: .yahooChart
            ),
            StockQuoteSnapshot(
                symbol: "NVDA",
                name: "英伟达",
                exchange: "NASDAQ",
                currency: "USD",
                price: 128.40,
                change: -2.15,
                changePercent: -1.65,
                dayLow: 127.8,
                dayHigh: 131.2,
                postPrice: 128.05,
                postChangePercent: -0.27,
                sparkline: [132, 131.5, 130.8, 131.2, 129.6, 130.1, 128.9, 129.2, 128.40],
                marketState: "POST",
                updatedAt: Date(),
                isStale: false,
                provider: .yahooChart
            ),
        ]
    }
}

struct StockIslandStaticView: View {
    let snapshots: [StockQuoteSnapshot]
    @ObservedObject var settings: StockSettings
    /// 单卡最小宽；岛上真机默认 168，设置预览宜更窄。
    var cardMinWidth: CGFloat = 168
    /// 库卡 / 设置预览：缩小分时与内边距，避免卡片显得过长。
    var compactChrome: Bool = false

    var body: some View {
        let count = max(snapshots.count, 1)
        let gap: CGFloat = compactChrome ? 6 : 8
        HStack(alignment: .top, spacing: gap) {
            ForEach(snapshots) { snap in
                StockIslandCard(
                    snap: snap,
                    settings: settings,
                    compactChrome: compactChrome
                )
                .frame(width: cardMinWidth, alignment: .leading)
            }
        }
        .frame(width: CGFloat(count) * cardMinWidth + CGFloat(max(count - 1, 0)) * gap)
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct StockIslandCard: View {
    let snap: StockQuoteSnapshot
    @ObservedObject var settings: StockSettings
    var compactChrome: Bool = false

    private var positiveTone: Bool {
        StockSession.isPositiveTone(isUp: snap.isUp, convention: settings.colorConvention)
    }

    private var tone: Color {
        positiveTone
            ? Color(red: 0.45, green: 0.99, blue: 0.53)
            : Color(red: 1.0, green: 0.73, blue: 0.71)
    }

    private var toneMuted: Color {
        positiveTone
            ? Color(red: 0.0, green: 0.45, blue: 0.16).opacity(0.45)
            : Color(red: 0.58, green: 0.0, blue: 0.04).opacity(0.45)
    }

    var body: some View {
        let priceSize: CGFloat = compactChrome ? 15 : 18
        let sparkH: CGFloat = compactChrome ? 22 : 36
        let pad: CGFloat = compactChrome ? 8 : 10
        VStack(alignment: .leading, spacing: compactChrome ? 3 : 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    // 代码与名称分行：代码始终完整可见，不被长名称挤掉。
                    Text(snap.symbol)
                        .font(.system(size: compactChrome ? 12 : 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(displayName(for: snap))
                        .font(.system(size: compactChrome ? 9 : 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                    if settings.priceFormat == .percentPriority {
                        Text(StockSession.formatPercent(snap.changePercent))
                            .font(.system(size: priceSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    } else {
                        Text(StockSession.formatPrice(
                            snap.price,
                            currency: snap.currency,
                            format: settings.priceFormat
                        ))
                        .font(.system(size: priceSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: snap.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(StockSession.formatPercent(snap.changePercent))
                            .font(.system(size: compactChrome ? 10 : 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(tone)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(toneMuted))

                    Text(StockSession.formatSigned(snap.change))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(tone.opacity(0.9))
                }
            }

            if settings.showSparkline {
                StockSparklineView(points: snap.sparkline, positiveTone: positiveTone)
                    .frame(height: sparkH)
                    .padding(.vertical, compactChrome ? 0 : 2)
            }

            if !compactChrome {
                HStack(spacing: 6) {
                    if let post = snap.postPrice, let postPct = snap.postChangePercent {
                        Text(
                            "\(L10n.Stocks.afterHours) \(StockSession.formatPrice(post, currency: snap.currency, format: .adaptiveCurrency)) (\(StockSession.formatPercent(postPct)))"
                        )
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    dayRangeBar
                }
            }
        }
        .padding(pad)
        .background(
            RoundedRectangle(cornerRadius: compactChrome ? 12 : 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .opacity(snap.isStale ? 0.72 : 1)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(
            "\(snap.symbol)，\(displayName(for: snap))，\(snap.price)，\(StockSession.formatPercent(snap.changePercent))"
        )
    }

    /// 名称与代码相同时只显示一侧，避免「AAPL / AAPL」。
    private func displayName(for snap: StockQuoteSnapshot) -> String {
        let name = snap.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return snap.symbol }
        if name.caseInsensitiveCompare(snap.symbol) == .orderedSame { return snap.symbol }
        return name
    }

    private var dayRangeBar: some View {
        let low = snap.dayLow
        let high = snap.dayHigh
        let span = max(high - low, 0.01)
        let pos = min(max((snap.price - low) / span, 0), 1)
        return HStack(spacing: 4) {
            Text(String(format: "L %.1f", low))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tone.opacity(0.85))
                        .frame(width: max(4, geo.size.width * 0.28))
                        .offset(x: max(0, (geo.size.width - 4) * pos - geo.size.width * 0.14))
                }
            }
            .frame(width: 40, height: 4)
            Text(String(format: "H %.1f", high))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

struct StockSparklineView: View {
    let points: [Double]
    let positiveTone: Bool

    var body: some View {
        let stroke = positiveTone
            ? Color(red: 0.32, green: 0.88, blue: 0.44)
            : Color(red: 0.73, green: 0.10, blue: 0.10)
        GeometryReader { geo in
            let path = Self.linePath(points: points, in: geo.size)
            let fill = Self.fillPath(points: points, in: geo.size)
            ZStack {
                fill.fill(
                    LinearGradient(
                        colors: [stroke.opacity(0.32), stroke.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                path.stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = Self.lastPoint(points: points, in: geo.size) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(stroke, lineWidth: 1.5))
                        .position(last)
                }
            }
        }
    }

    private static func normalized(_ points: [Double]) -> [Double] {
        guard let minV = points.min(), let maxV = points.max(), maxV > minV else {
            return points.map { _ in 0.5 }
        }
        return points.map { 1 - (($0 - minV) / (maxV - minV)) }
    }

    private static func linePath(points: [Double], in size: CGSize) -> Path {
        let norms = normalized(points)
        var path = Path()
        guard norms.count > 1 else { return path }
        for (i, y) in norms.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(norms.count - 1)
            let pt = CGPoint(x: x, y: size.height * CGFloat(y) * 0.85 + size.height * 0.08)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private static func fillPath(points: [Double], in size: CGSize) -> Path {
        var path = linePath(points: points, in: size)
        guard !points.isEmpty else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private static func lastPoint(points: [Double], in size: CGSize) -> CGPoint? {
        let norms = normalized(points)
        guard let y = norms.last, norms.count > 1 else { return nil }
        return CGPoint(
            x: size.width,
            y: size.height * CGFloat(y) * 0.85 + size.height * 0.08
        )
    }
}
