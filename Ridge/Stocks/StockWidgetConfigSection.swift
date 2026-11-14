import SwiftUI

/// 股票设置：岛样张 + 自选固钉 + 显示偏好。
struct StockWidgetConfigSection: View {
    @ObservedObject private var settings = StockSettings.shared
    @ObservedObject private var session = StockSession.shared

    @State private var searchText = ""
    @State private var searchResults: [StockSearchHit] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsIslandPreviewCard(widgetID: "builtin.stocks")
                        Text(L10n.Stocks.sparklineExplainer)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    watchlistCard
                    preferencesCard
                    if let err = session.lastError {
                        Text(err)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.error)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, SettingsChrome.Spacing.pageHorizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreDefaults()
                session.refresh(reason: "restoreDefaults")
            }
        }
        .background(SettingsChrome.pageBackground)
        .onAppear {
            session.start()
            AppLog.info("Stocks", "配置页已显示", ["pins": settings.pins.count])
        }
    }

    // MARK: - Watchlist

    private var dataSourceChip: some View {
        HStack(spacing: 6) {
            Text(L10n.Stocks.dataSourceLabel)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            Circle()
                .fill(session.dataSourceIsLive ? SettingsChrome.secondary : SettingsChrome.onSurfaceVariant.opacity(0.45))
                .frame(width: 6, height: 6)
            Text(session.dataSourceShortName)
                .font(SettingsChrome.Font.chipSelected)
                .foregroundStyle(SettingsChrome.onSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(SettingsChrome.surfaceContainer)
        )
        .help(L10n.Stocks.dataSourceHint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.Stocks.dataSourceLabel)\(session.dataSourceShortName)")
    }

    private var watchlistCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1")
                            .font(SettingsChrome.Font.iconTile)
                            .foregroundStyle(SettingsChrome.primary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(SettingsChrome.primary.opacity(0.12))
                            )
                        Text(L10n.Stocks.watchlistTitle(settings.pins.count, StockSettings.maxPins))
                            .font(SettingsChrome.Font.sectionTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                    }
                    dataSourceChip
                    Spacer(minLength: 8)
                    Text(L10n.Stocks.dragHint)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        searchFieldChrome
                        Button {
                            Task { await addFromSearchField() }
                        } label: {
                            Label(L10n.Stocks.addSymbol, systemImage: "plus")
                                .font(SettingsChrome.Font.chip)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(settings.isFull ? SettingsChrome.outline : SettingsChrome.primary)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            settings.isFull
                                || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    // 下拉挂在搜索框下方（进布局流，避免被 ScrollView 裁切）。
                    if showsSearchDropdown {
                        searchDropdownPanel
                    }
                }

                if settings.pins.isEmpty {
                    Text(L10n.Stocks.watchlistEmpty)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .padding(.vertical, 8)
                } else {
                    // 系统 List.onMove：整行拖动排序，避免手写 DropDelegate。
                    List {
                        ForEach(settings.pins) { pin in
                            pinRow(pin)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .selectionDisabled()
                        }
                        .onMove { source, destination in
                            settings.movePins(from: source, to: destination)
                            session.refresh(reason: "reorder")
                            AppLog.info("Stocks", "自选排序完成", ["count": settings.pins.count])
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, 56)
                    .frame(height: CGFloat(settings.pins.count) * 72)
                }
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private var showsSearchDropdown: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isSearching || searchError != nil || !searchResults.isEmpty)
    }

    private var searchFieldChrome: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SettingsChrome.outline)
            TextField(L10n.Stocks.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(SettingsChrome.Font.body)
                .onChange(of: searchText) { _, value in
                    scheduleSearch(for: value)
                }
                .onSubmit { Task { await addFromSearchField() } }
            if !searchText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SettingsChrome.outline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private var searchDropdownPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.Stocks.searchResultsHeader)
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.outline)
                Spacer(minLength: 8)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if let searchError, searchResults.isEmpty {
                Text(searchError)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if searchResults.isEmpty, isSearching {
                Text(L10n.Stocks.searching)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(searchResults) { hit in
                        searchRow(hit)
                        if hit.id != searchResults.last?.id {
                            SettingsHairline()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
    }

    private func searchRow(_ hit: StockSearchHit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.symbol)
                        .font(SettingsChrome.Font.label)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(hit.name)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .lineLimit(1)
                }
                Text(hit.exchange)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.outline)
            }
            Spacer(minLength: 8)
            Button {
                addHit(hit)
            } label: {
                Text(L10n.Stocks.add)
                    .font(SettingsChrome.Font.chip)
                    .foregroundStyle(settings.isFull ? SettingsChrome.outline : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settings.isFull ? SettingsChrome.surfaceContainer : SettingsChrome.primary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(settings.isFull)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func pinDisplayName(_ pin: StockPin, snap: StockQuoteSnapshot?) -> String {
        let custom = pin.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let remote = snap?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !remote.isEmpty, remote.caseInsensitiveCompare(pin.symbol) != .orderedSame {
            return remote
        }
        return pin.symbol
    }

    private func pinSubtitle(_ pin: StockPin, snap: StockQuoteSnapshot?) -> String {
        if let snap {
            let price = StockSession.formatPrice(
                snap.price,
                currency: snap.currency,
                format: .adaptiveCurrency
            )
            let source: String = {
                if let provider = snap.provider {
                    return L10n.Stocks.providerName(provider)
                }
                if snap.isStale { return L10n.Stocks.dataSourceCached }
                return L10n.Stocks.dataSourceUnknown
            }()
            if snap.isStale {
                return "\(pin.symbol) · \(price) · \(source) · \(L10n.Stocks.quoteStale)"
            }
            return "\(pin.symbol) · \(price) · \(source)"
        }
        if session.isRefreshing {
            return "\(pin.symbol) · \(L10n.Stocks.quoteUpdating)"
        }
        return "\(pin.symbol) · \(L10n.Stocks.quoteUnavailable)"
    }

    private func pinRow(_ pin: StockPin) -> some View {
        let snap = session.snapshots.first {
            $0.symbol.caseInsensitiveCompare(pin.symbol) == .orderedSame
        }
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .frame(width: 22, height: 28)
                .help(L10n.Stocks.dragHint)

            VStack(alignment: .leading, spacing: 2) {
                Text(pinDisplayName(pin, snap: snap))
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                Text(pinSubtitle(pin, snap: snap))
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(
                        snap == nil
                            ? SettingsChrome.outline
                            : SettingsChrome.onSurfaceVariant
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                settings.removePin(symbol: pin.symbol)
                session.refresh(reason: "remove")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsChrome.outline)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.Stocks.remove)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(SettingsChrome.Font.iconTile)
                        .foregroundStyle(SettingsChrome.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.primary.opacity(0.12))
                        )
                    Text(L10n.Stocks.prefsTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                }
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.top, SettingsChrome.Spacing.cardPadding)
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Stocks.colorTitle)
                        .font(SettingsChrome.Font.rowTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Stocks.colorSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    SettingsSegmentedControl(
                        items: [
                            SettingsSegmentedControl.Item(
                                id: "intl",
                                title: L10n.Stocks.colorInternational,
                                selected: settings.colorConvention == .international,
                                leadingDot: SettingsChrome.secondary
                            ) {
                                settings.colorConvention = .international
                            },
                            SettingsSegmentedControl.Item(
                                id: "cn",
                                title: L10n.Stocks.colorGreaterChina,
                                selected: settings.colorConvention == .greaterChina,
                                leadingDot: SettingsChrome.error
                            ) {
                                settings.colorConvention = .greaterChina
                            },
                        ]
                    )
                }
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.vertical, 8)

                SettingsHairline()

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Stocks.formatTitle)
                        .font(SettingsChrome.Font.rowTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Stocks.formatSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    SettingsSegmentedControl(
                        items: [
                            SettingsSegmentedControl.Item(
                                id: "adaptive",
                                title: L10n.Stocks.formatAdaptive,
                                selected: settings.priceFormat == .adaptiveCurrency
                            ) {
                                settings.priceFormat = .adaptiveCurrency
                            },
                            SettingsSegmentedControl.Item(
                                id: "bare",
                                title: L10n.Stocks.formatBare,
                                selected: settings.priceFormat == .bareNumber
                            ) {
                                settings.priceFormat = .bareNumber
                            },
                            SettingsSegmentedControl.Item(
                                id: "pct",
                                title: L10n.Stocks.formatPercent,
                                selected: settings.priceFormat == .percentPriority
                            ) {
                                settings.priceFormat = .percentPriority
                            },
                        ]
                    )
                }
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.vertical, 8)

                SettingsHairline()

                SettingsSwitchRow(
                    title: L10n.Stocks.sparklineTitle,
                    subtitle: L10n.Stocks.sparklineSubtitle,
                    isOn: $settings.showSparkline
                )
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Actions

    /// 输入即搜：本地别名立刻出结果，再防抖补 Yahoo 远程结果。
    private func scheduleSearch(for raw: String) {
        searchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        // 先本地命中，保证「苹果 / 腾讯」也能立刻出下拉。
        let local = StockSearchIndex.localHits(for: q)
        searchResults = local
        searchError = nil
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            await runSearch(query: q, generation: generation)
        }
    }

    private func runSearch(query: String? = nil, generation: Int? = nil) async {
        let q = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            let hits = try await StockYahooClient.search(query: q)
            guard !Task.isCancelled else { return }
            if let generation, generation != searchGeneration { return }
            searchResults = hits
            searchError = hits.isEmpty ? L10n.Stocks.searchEmpty : nil
            AppLog.warn("Stocks", "搜索完成", ["q": q, "hits": hits.count])
        } catch is CancellationError {
            return
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
            guard !Task.isCancelled else { return }
            if let generation, generation != searchGeneration { return }
            if searchResults.isEmpty {
                searchError = L10n.Stocks.searchFailed
            }
            AppLog.warn("Stocks", "搜索失败", ["q": q, "error": String(describing: error)])
        }
        if generation == nil || generation == searchGeneration {
            isSearching = false
        }
    }

    private func addFromSearchField() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return }
        if let hit = searchResults.first(where: {
            $0.symbol.caseInsensitiveCompare(q) == .orderedSame
        }) {
            addHit(hit)
            return
        }
        await runSearch(query: q)
        if let hit = searchResults.first {
            addHit(hit)
        } else if settings.addPin(StockPin(symbol: q, displayName: "")) {
            clearSearch()
            session.refresh(reason: "addDirect")
        }
    }

    private func addHit(_ hit: StockSearchHit) {
        if settings.addPin(StockPin(symbol: hit.symbol, displayName: hit.name)) {
            clearSearch()
            session.refresh(reason: "addHit")
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1
        searchText = ""
        searchResults = []
        searchError = nil
        isSearching = false
    }
}

