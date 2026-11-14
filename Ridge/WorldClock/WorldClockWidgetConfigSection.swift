import SwiftUI

/// 世界时钟设置：岛样张 + 搜索添加 + 固钉管理 + 胶囊呈现偏好。
struct WorldClockWidgetConfigSection: View {
    @ObservedObject private var settings = WorldClockSettings.shared
    @ObservedObject private var session = WorldClockSession.shared

    @State private var searchText = ""
    @State private var searchResults: [WorldClockCatalogEntry] = []
    @State private var draggingCityID: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    SettingsIslandPreviewCard(widgetID: "builtin.worldClock")
                    searchCard
                    pinnedListCard
                    preferencesCard
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
            AppLog.info("WorldClock", "配置页已显示", [
                "cities": settings.cities.count,
                "catalog": WorldClockCatalog.entries.count
            ])
        }
    }

    // MARK: - Search

    private var searchCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(SettingsChrome.Font.iconTile)
                        .foregroundStyle(SettingsChrome.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.primary.opacity(0.12))
                        )
                    Text(L10n.WorldClock.searchTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Spacer(minLength: 8)
                    Text(L10n.WorldClock.searchHint)
                        .font(SettingsChrome.Font.footnote)
                        .foregroundStyle(SettingsChrome.outline)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SettingsChrome.outline)
                    TextField(L10n.WorldClock.searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(SettingsChrome.Font.body)
                        .onChange(of: searchText) { _, value in
                            searchResults = WorldClockCatalog.search(value)
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
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

                if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { entry in
                            searchResultRow(entry)
                            if entry.id != searchResults.last?.id {
                                SettingsHairline()
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(SettingsChrome.surfaceContainerLow)
                    )
                }
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private func searchResultRow(_ entry: WorldClockCatalogEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.flag)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(entry.cityName), \(entry.region)")
                        .font(SettingsChrome.Font.label)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(entry.timeZoneID)
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.outline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(SettingsChrome.surfaceContainer)
                        )
                }
            }
            Spacer(minLength: 8)
            Button {
                addEntry(entry)
            } label: {
                Label(L10n.WorldClock.add, systemImage: "plus")
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

    private func addEntry(_ entry: WorldClockCatalogEntry) {
        let city = WorldClockCatalog.makeCity(from: entry)
        if settings.addCity(city) {
            searchText = ""
            searchResults = []
            session.refresh(reason: "addCity")
        }
    }

    // MARK: - Pinned list

    private var pinnedListCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(SettingsChrome.Font.iconTile)
                        .foregroundStyle(SettingsChrome.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.secondary.opacity(0.12))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.WorldClock.pinnedTitle)
                            .font(SettingsChrome.Font.sectionTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.WorldClock.pinnedSubtitle)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(L10n.WorldClock.slotUsage(settings.cities.count, WorldClockSettings.maxCities))
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(SettingsChrome.primary.opacity(0.12))
                        )
                }

                if settings.cities.isEmpty {
                    Text(L10n.WorldClock.pinnedEmpty)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(settings.cities) { city in
                            pinnedRow(city)
                                .opacity(draggingCityID == city.id ? 0.4 : 1)
                                .onDrop(
                                    of: [.text, .plainText, .utf8PlainText],
                                    delegate: WorldClockCityReorderDropDelegate(
                                        targetID: city.id,
                                        draggingID: $draggingCityID,
                                        settings: settings,
                                        session: session
                                    )
                                )
                        }
                    }
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.86),
                        value: settings.cities.map(\.id)
                    )
                }
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private func pinnedRow(_ city: WorldClockCity) -> some View {
        let snap = session.snapshots.first(where: { $0.id == city.id })
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .frame(width: 22, height: 28)
                .contentShape(Rectangle())
                .help(L10n.WorldClock.dragHandleHelp)
                .onDrag {
                    draggingCityID = city.id
                    AppLog.debug("WorldClock", "开始拖拽城市行", ["id": city.id, "city": city.cityName])
                    return NSItemProvider(object: city.id as NSString)
                } preview: {
                    pinnedDragPreview(city, snap: snap)
                }

            Text(city.flag)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsChrome.cardBackground)
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(city.cityName), \(city.region)")
                        .font(SettingsChrome.Font.cardTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(city.timeZoneID)
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(SettingsChrome.surfaceContainer)
                        )
                }
                HStack(spacing: 6) {
                    Text(L10n.WorldClock.aliasLabel)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    TextField(
                        "",
                        text: aliasBinding(for: city.id),
                        prompt: Text(L10n.WorldClock.aliasPlaceholder)
                            .font(SettingsChrome.Font.chip)
                            .foregroundStyle(SettingsChrome.placeholder)
                    )
                    .textFieldStyle(.plain)
                    .font(SettingsChrome.Font.chip)
                    .foregroundStyle(SettingsChrome.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(width: 120, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SettingsChrome.cardBackground)
                    )
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(snap?.timeText ?? "--:--")
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
                HStack(spacing: 6) {
                    if let badge = snap?.offsetBadge, !badge.isEmpty {
                        Text(badge)
                            .font(SettingsChrome.Font.footnote)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    if let snap {
                        zoneStatusBadge(snap)
                    }
                }
            }

            Button {
                settings.removeCity(id: city.id)
                session.refresh(reason: "remove")
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsChrome.outline)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.WorldClock.remove)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
        )
    }

    private func pinnedDragPreview(_ city: WorldClockCity, snap: WorldClockCitySnapshot?) -> some View {
        HStack(spacing: 10) {
            Text(city.flag).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(city.displayTitle)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(city.cityName)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Text(snap?.timeText ?? "--:--")
                .font(SettingsChrome.Font.monoEmphasis)
                .foregroundStyle(SettingsChrome.onSurface)
        }
        .padding(12)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        )
    }

    /// 夏令时：薄荷绿底 + 深绿字；否则灰底灰字（对齐设计稿）。
    @ViewBuilder
    private func zoneStatusBadge(_ snap: WorldClockCitySnapshot) -> some View {
        let text = snap.zoneStatusText
        if text.isEmpty {
            EmptyView()
        } else if snap.isDaylightSaving {
            Text(text)
                .font(SettingsChrome.Font.badgeTiny)
                .foregroundStyle(SettingsChrome.onSecondaryContainer)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(SettingsChrome.secondaryContainer)
                )
        } else {
            Text(text)
                .font(SettingsChrome.Font.badgeTiny)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(SettingsChrome.surfaceContainer)
                )
        }
    }

    private func aliasBinding(for id: String) -> Binding<String> {
        Binding(
            get: { settings.cities.first(where: { $0.id == id })?.alias ?? "" },
            set: { settings.updateAlias(id: id, alias: $0) }
        )
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(SettingsChrome.Font.iconTile)
                        .foregroundStyle(Color(red: 0.30, green: 0.29, blue: 0.79))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.30, green: 0.29, blue: 0.79).opacity(0.12))
                        )
                    Text(L10n.WorldClock.prefsTitle)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                }
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.top, SettingsChrome.Spacing.cardPadding)
                .padding(.bottom, 8)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.WorldClock.timeFormatTitle)
                            .font(SettingsChrome.Font.rowTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.WorldClock.timeFormatSubtitle)
                            .font(SettingsChrome.Font.caption)
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    Spacer(minLength: 8)
                    SettingsSegmentedControl(
                        items: [
                            SettingsSegmentedControl.Item(
                                id: "24h",
                                title: L10n.WorldClock.format24h,
                                selected: settings.use24Hour
                            ) {
                                settings.use24Hour = true
                                session.refresh(reason: "format24")
                            },
                            SettingsSegmentedControl.Item(
                                id: "12h",
                                title: L10n.WorldClock.format12h,
                                selected: !settings.use24Hour
                            ) {
                                settings.use24Hour = false
                                session.refresh(reason: "format12")
                            },
                        ]
                    )
                    .frame(width: 120)
                }
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .padding(.vertical, 8)

                SettingsHairline()

                SettingsSwitchRow(
                    title: L10n.WorldClock.dayNightTitle,
                    subtitle: L10n.WorldClock.dayNightSubtitle,
                    isOn: $settings.showDayNightIcons
                )
                SettingsHairline()
                SettingsSwitchRow(
                    title: L10n.WorldClock.offsetTitle,
                    subtitle: L10n.WorldClock.offsetSubtitle,
                    isOn: $settings.showRelativeOffset
                )
                .padding(.bottom, 8)
            }
        }
    }
}

/// 松手落在目标行上时交换固钉顺序。
private struct WorldClockCityReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let settings: WorldClockSettings
    let session: WorldClockSession

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let finishedID = draggingID
        draggingID = nil
        guard let finishedID, finishedID != targetID else { return false }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            _ = settings.moveCity(draggedID: finishedID, onto: targetID)
        }
        session.refresh(reason: "reorder")
        return true
    }
}
