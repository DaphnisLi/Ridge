import Combine
import CoreGraphics
import Foundation

enum IslandAppearance: Equatable {
    case compact
    case expanded
}

@MainActor
final class IslandViewModel: ObservableObject {
    @Published var appearance: IslandAppearance = .compact
    @Published var isHiddenForFullscreen = false
    @Published var isVisibleOnDisplay = true
    @Published var notchHeight: CGFloat = 32
    @Published var notchWidth: CGFloat = 160
    /// 展开宽度上限（屏宽减去边距）；与 NotchGeometry.maxExpandedWidth 一致。
    @Published var maxExpandedWidth: CGFloat = 2000
    /// 当前可见面板尺寸：收起为刘海/待命宽高；展开由内容测量 + IslandChrome 撑开。
    @Published var panelSize: CGSize = CGSize(width: 160, height: 32)

    var isExpanded: Bool { appearance == .expanded }

    func toggle() {
        appearance = isExpanded ? .compact : .expanded
    }

    func expand() {
        appearance = .expanded
    }

    func collapse() {
        appearance = .compact
    }

    /// 内容 Preference 上报后写入；变化过小则忽略，避免布局抖动。
    func applyMeasuredPanelSize(_ raw: CGSize) {
        let next = IslandPanelSizing.clamp(
            raw,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            maxWidth: maxExpandedWidth
        )
        guard abs(next.width - panelSize.width) > 0.5
            || abs(next.height - panelSize.height) > 0.5
        else { return }
        panelSize = next
        AppLog.debug("Island", "面板尺寸由内容更新", [
            "w": next.width,
            "h": next.height,
            "expanded": isExpanded
        ])
    }
}
