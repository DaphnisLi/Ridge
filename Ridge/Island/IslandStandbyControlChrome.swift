import CoreGraphics

/// 岛上待命圆钮视觉 + 不可见命中外扩（可单测锁定）。
/// 修「点不中」时只动 `hitPad`（配负 padding），禁止把 `visualDiameter` 顺手做大。
enum IslandStandbyControlChrome {
    /// 暂停 / 结束等圆钮视觉直径。
    static let visualDiameter: CGFloat = 26
    /// 命中外扩；须配合负 padding 收回布局，视觉尺寸不变。
    static let hitPad: CGFloat = 10
    /// 圆钮内 SF Symbol 字号。
    static let symbolPointSize: CGFloat = 9
}
