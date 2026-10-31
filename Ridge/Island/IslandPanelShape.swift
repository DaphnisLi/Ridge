import SwiftUI

/// 上直角、下圆角的岛面板路径。
/// 不用 `UnevenRoundedRectangle` + continuous：变宽后下圆角容易被压成一小块。
struct IslandPanelShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.height / 2, rect.width / 2))
        var path = Path()

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))

        if r > 0.5 {
            path.addArc(
                center: CGPoint(x: rect.width - r, y: rect.height - r),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        }

        path.addLine(to: CGPoint(x: r, y: rect.height))

        if r > 0.5 {
            path.addArc(
                center: CGPoint(x: r, y: rect.height - r),
                radius: r,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: 0, y: rect.height))
        }

        path.closeSubpath()
        return path
    }
}
