import AppKit
import Foundation
import SwiftUI

/// 系统空态岛：尚无用户小组件争夺展示时出现。不进设置排序，不可被关掉。
@MainActor
final class EmptyIslandWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: SystemWidgetID.empty,
        displayName: "Ridge",
        summary: "尚未添加小组件时的提示",
        version: "1.0.0",
        source: .builtin,
        kind: .systemEmpty,
        supportsPinning: false
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

    var body: some View {
        VStack(spacing: 10) {
            Text("尚未添加小组件")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Text("启用或添加后，内容会显示在这里")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            Button(action: onAdd) {
                Text("去添加小组件")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
