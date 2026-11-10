import AppKit
import SwiftUI

/// 用不透明 CAShapeLayer + device RGB 画岛底色。
/// SwiftUI `Color` 经透明 NSPanel 合成时常被抬灰；device 色绕过 ColorSync，是屏幕能出的最黑。
struct IslandOpaqueFillView: NSViewRepresentable {
    var bottomRadius: CGFloat
    var outlineStyle: IslandOutlineStyle
    var fill: NSColor

    func makeNSView(context: Context) -> IslandOpaqueFillNSView {
        IslandOpaqueFillNSView()
    }

    func updateNSView(_ nsView: IslandOpaqueFillNSView, context: Context) {
        nsView.apply(fill: fill, bottomRadius: bottomRadius, outlineStyle: outlineStyle)
    }
}

final class IslandOpaqueFillNSView: NSView {
    private let shapeLayer = CAShapeLayer()
    private var bottomRadius: CGFloat = 0
    private var outlineStyle: IslandOutlineStyle = .panel
    private var fill: NSColor = IslandTheme.notchDeviceBlack

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        shapeLayer.fillColor = fill.cgColor
        shapeLayer.strokeColor = nil
        shapeLayer.opacity = 1
        shapeLayer.allowsEdgeAntialiasing = true
        layer?.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(fill: NSColor, bottomRadius: CGFloat, outlineStyle: IslandOutlineStyle) {
        let fillChanged = self.fill != fill
        let radiusChanged = abs(self.bottomRadius - bottomRadius) > 0.05
        let styleChanged = self.outlineStyle != outlineStyle
        self.fill = fill
        self.bottomRadius = bottomRadius
        self.outlineStyle = outlineStyle
        if fillChanged {
            shapeLayer.fillColor = fill.cgColor
        }
        if fillChanged || radiusChanged || styleChanged || shapeLayer.path == nil {
            rebuildPath()
        }
    }

    override func layout() {
        super.layout()
        shapeLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        shapeLayer.frame = bounds
        rebuildPath()
    }

    private func rebuildPath() {
        guard bounds.width > 0.5, bounds.height > 0.5 else {
            shapeLayer.path = nil
            return
        }
        shapeLayer.path = IslandOutlinePath
            .path(style: outlineStyle, bottomRadius: bottomRadius, in: bounds)
            .cgPath
    }
}

extension IslandTheme {
    /// 刘海级纯黑：device RGB，不经校准抬升。
    static let notchDeviceBlack = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)

    /// 岛底 AppKit 填充色（经典黑走 device，其余走 sRGB）。
    var nsFillColor: NSColor {
        switch self {
        case .midnight:
            return Self.notchDeviceBlack
        case .afterglow:
            return NSColor(srgbRed: 0.22, green: 0.11, blue: 0.09, alpha: 1)
        case .lumenPark:
            return NSColor(srgbRed: 0.09, green: 0.18, blue: 0.13, alpha: 1)
        case .graphite:
            return NSColor(srgbRed: 0.18, green: 0.18, blue: 0.19, alpha: 1)
        case .tide:
            return NSColor(srgbRed: 0.06, green: 0.14, blue: 0.26, alpha: 1)
        }
    }
}
