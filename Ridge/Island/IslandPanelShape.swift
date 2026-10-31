import SwiftUI

/// 上直角、下圆角。
/// 不声明 `animatableData`：半径/尺寸变化时每帧按 `rect` 重算路径，避免 Shape 插值把下角拧成一小段。
struct IslandPanelShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 0.5, h > 0.5 else { return Path() }

        let r = min(max(0, bottomRadius), h / 2, w / 2)
        var path = Path()

        // 顶边左 → 右（直角贴顶）
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        if r < 0.5 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }

        // 右直边 → 右下四分之一圆（圆心在内侧，从东到南）
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // 底边 → 左下四分之一圆（从南到西）
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}
