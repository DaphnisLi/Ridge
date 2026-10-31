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

    /// 内容区占位切换用（后续接 widget id）。
    @Published var contentToken: Int = 0

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
