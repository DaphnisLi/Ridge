import SwiftUI

/// 世界时钟岛上展开：最多四列城市卡（根视图无外圈 padding）。
struct WorldClockIslandView: View {
    @ObservedObject var session: WorldClockSession
    @ObservedObject var settings: WorldClockSettings

    var body: some View {
        let items = session.snapshots
        Group {
            if items.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(items) { snap in
                        cityCard(snap)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(minWidth: items.isEmpty ? 220 : CGFloat(max(items.count, 1)) * 118)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        Text(L10n.WorldClock.emptyIsland)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.vertical, 10)
    }

    private func cityCard(_ snap: WorldClockCitySnapshot) -> some View {
        let tint = Color(
            red: snap.dayPhase.tint.0,
            green: snap.dayPhase.tint.1,
            blue: snap.dayPhase.tint.2
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(snap.city.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(snap.city.flag)
                    .font(.system(size: 11))
            }
            Text(snap.city.displayCityName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snap.timeText)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(snap.zoneAbbreviation)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .padding(.vertical, 1)
            HStack(spacing: 4) {
                if settings.showRelativeOffset, !snap.offsetBadge.isEmpty {
                    Text(snap.offsetBadge)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if settings.showDayNightIcons {
                    Image(systemName: snap.dayPhase.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .accessibilityLabel(
            "\(snap.city.displayTitle)，\(snap.timeText)，\(snap.offsetBadge)"
        )
    }

    static func previewSample() -> some View {
        WorldClockIslandPreviewHost()
    }
}

/// 设置预览：用当前设置城市；若空则用目录默认四城假数据。
private struct WorldClockIslandPreviewHost: View {
    @ObservedObject private var settings = WorldClockSettings.shared

    var body: some View {
        let now = Date()
        let local = TimeZone.current
        let source = settings.cities.isEmpty ? Self.fallbackCities : settings.cities
        let snaps = source.map { city in
            WorldClockSession.makeSnapshot(
                city: city,
                now: now,
                local: local,
                use24Hour: settings.use24Hour,
                showOffset: settings.showRelativeOffset,
                isPrimary: city.id == settings.primaryCityID
            )
        }
        return WorldClockIslandStaticView(
            snapshots: snaps,
            showOffset: settings.showRelativeOffset,
            showDayNight: settings.showDayNightIcons
        )
    }

    private static var fallbackCities: [WorldClockCity] {
        ["London", "San Francisco", "Tokyo"].compactMap { name in
            WorldClockCatalog.entries.first(where: { $0.cityName == name }).map {
                WorldClockCatalog.makeCity(from: $0, alias: "")
            }
        }
    }
}

struct WorldClockIslandStaticView: View {
    let snapshots: [WorldClockCitySnapshot]
    var showOffset: Bool = true
    var showDayNight: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(snapshots) { snap in
                card(snap)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: CGFloat(max(snapshots.count, 1)) * 118)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func card(_ snap: WorldClockCitySnapshot) -> some View {
        let tint = Color(
            red: snap.dayPhase.tint.0,
            green: snap.dayPhase.tint.1,
            blue: snap.dayPhase.tint.2
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(snap.city.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(snap.city.flag)
                    .font(.system(size: 11))
            }
            Text(snap.city.displayCityName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snap.timeText)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(snap.zoneAbbreviation)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
            }
            HStack {
                if showOffset, !snap.offsetBadge.isEmpty {
                    Text(snap.offsetBadge)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                if showDayNight {
                    Image(systemName: snap.dayPhase.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
