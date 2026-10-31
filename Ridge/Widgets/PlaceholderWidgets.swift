import Foundation
import SwiftUI

// MARK: - 媒体占位

@MainActor
final class MediaPlaceholderWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.media",
        displayName: "正在播放",
        summary: "媒体占位，后续接 Now Playing",
        source: .builtin,
        kind: .content
    )

    private let context: WidgetContext
    var priority: Int = 0
    private(set) var wantsDisplay = true
    private(set) var requestedAt = Date()

    init(context: WidgetContext) {
        self.context = context
    }

    func makeView() -> AnyView {
        AnyView(
            PlaceholderWidgetChrome(
                symbol: "music.note",
                title: "未在播放",
                subtitle: "媒体小组件占位"
            )
        )
    }

    func onAppear() { context.log("媒体占位 onAppear") }
    func onDisappear() { context.log("媒体占位 onDisappear") }
    func refresh() {}
}

// MARK: - 会议占位

@MainActor
final class MeetingPlaceholderWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.meeting",
        displayName: "下一场会议",
        summary: "日历占位，后续接日程倒计时",
        source: .builtin,
        kind: .content
    )

    private let context: WidgetContext
    var priority: Int = 0
    private(set) var wantsDisplay = true
    private(set) var requestedAt = Date()

    init(context: WidgetContext) {
        self.context = context
    }

    func makeView() -> AnyView {
        AnyView(
            PlaceholderWidgetChrome(
                symbol: "calendar",
                title: "暂无日程",
                subtitle: "会议小组件占位"
            )
        )
    }

    func onAppear() { context.log("会议占位 onAppear") }
    func onDisappear() { context.log("会议占位 onDisappear") }
    func refresh() {}
}

// MARK: - 系统状态占位

@MainActor
final class StatusPlaceholderWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.status",
        displayName: "系统状态",
        summary: "状态占位，后续接电量 / 网络等",
        source: .builtin,
        kind: .content
    )

    private let context: WidgetContext
    var priority: Int = 0
    private(set) var wantsDisplay = true
    private(set) var requestedAt = Date()

    init(context: WidgetContext) {
        self.context = context
    }

    func makeView() -> AnyView {
        AnyView(
            PlaceholderWidgetChrome(
                symbol: "battery.100",
                title: "状态正常",
                subtitle: "系统状态占位"
            )
        )
    }

    func onAppear() { context.log("状态占位 onAppear") }
    func onDisappear() { context.log("状态占位 onDisappear") }
    func refresh() {}
}

// MARK: - 共用占位 UI

private struct PlaceholderWidgetChrome: View {
    let symbol: String
    let title: String
    let subtitle: String
    @Environment(\.islandPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.icon)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.title)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
