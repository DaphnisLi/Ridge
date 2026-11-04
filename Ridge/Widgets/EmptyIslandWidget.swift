import AppKit
import Foundation
import SwiftUI

/// 系统空态岛：尚无用户小组件争夺展示时出现。不进设置排序，不可被关掉。
@MainActor
final class EmptyIslandWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: SystemWidgetID.empty,
        displayName: "Ridge",
        summary: L10n.Widgets.emptySummary,
        version: "1.0.0",
        source: .builtin,
        kind: .systemEmpty,
        supportsPinning: false,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast

    init(context: WidgetContext) {
        self.context = context
    }

    func makeView() -> AnyView {
        AnyView(EmptyIslandView(onAdd: { [weak self] in
            self?.context.openSettings()
        }))
    }

    func onAppear() {
        context.log("空态岛出现")
    }

    func onDisappear() {
        context.log("空态岛收起")
    }

    func refresh() {}
}

private struct EmptyIslandView: View {
    let onAdd: () -> Void
    @Environment(\.islandPalette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Text(L10n.Widgets.emptyTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.title)

            Text(L10n.Widgets.emptySubtitle)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)

            Button(action: onAdd) {
                Text(L10n.Widgets.emptyAdd)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accentForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.accentFill)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }
}
