import SwiftUI

/// 岛外壳轮廓：默认上直角、下圆角（贴顶融刘海）；`capsule` 仅保留给特殊样张；`circle` 给刘海右侧微岛。
enum IslandOutlineStyle: String, Equatable {
    /// 贴顶直角，底边圆角（真岛 / tip / 常驻默认）。
    case panel
    /// 四角等弧度（非默认；产品现要求 tip 也走 panel）。
    case capsule
    /// 正圆（「已复制」刘海右侧 Ø32 微岛）。
    case circle
}

/// 上直角、下圆角（常驻面板）。
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

/// 四角等弧度圆角矩形（瞬时提示 / 会议）：半径与原先面板下圆角同一套令牌。
/// 用手动画弧，保证 AppKit `CAShapeLayer` 与 SwiftUI clip 一致，避免 continuous roundedRect 转 cgPath 丢上角。
struct IslandCapsuleShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 0.5, h > 0.5 else { return Path() }

        let r = min(max(0, cornerRadius), h / 2, w / 2)
        if r < 0.5 {
            return Path(rect)
        }

        var path = Path()
        // 顶边（左上弧终点 → 右上弧起点）
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        // 右上
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        // 右下
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // 左下
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // 左上
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// 正圆路径（微岛）；半径取短边一半，居中于 `rect`。
struct IslandCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard side > 0.5 else { return Path() }
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        return Path(ellipseIn: CGRect(origin: origin, size: CGSize(width: side, height: side)))
    }
}

/// 按 `IslandOutlineStyle` 选择面板或四角等弧路径（SwiftUI clip / AppKit fill 共用）。
struct IslandOutlineShape: Shape {
    var style: IslandOutlineStyle
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        switch style {
        case .panel:
            return IslandPanelShape(bottomRadius: bottomRadius).path(in: rect)
        case .capsule:
            return IslandCapsuleShape(cornerRadius: bottomRadius).path(in: rect)
        case .circle:
            return IslandCircleShape().path(in: rect)
        }
    }
}

enum IslandOutlinePath {
    static func path(style: IslandOutlineStyle, bottomRadius: CGFloat, in rect: CGRect) -> Path {
        IslandOutlineShape(style: style, bottomRadius: bottomRadius).path(in: rect)
    }
}
