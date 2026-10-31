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
}
