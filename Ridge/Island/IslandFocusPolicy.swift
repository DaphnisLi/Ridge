import Foundation

/// 岛窗焦点策略：浮层不得长期抢走其它 App 的键盘 / 前台。
///
/// 历史翻车：悬停关穿透时 `activate(ignoringOtherApps:)` + `makeKey`；
/// 会议等常驻 tip 不收岛时又不 `resignKey` → 点别处无法聚焦输入。
enum IslandFocusPolicy {
    /// 指针进入可点区、仅关闭穿透时：不要抢前台。按钮靠 `acceptsFirstMouse`。
    static var shouldActivateAppWhenDisablingClickThrough: Bool { false }

    /// 展开岛（悬停 / 通知等）：默认不抢前台；文本输入路径自行 `IslandInteractionFocus.prepare`。
    static var shouldActivateAppOnExpand: Bool { false }

    /// 开启整窗穿透时：必须交出 key，并允许降回 accessory。
    static var shouldResignKeyWhenEnablingClickThrough: Bool { true }

    /// 普通岛上 mouseDown（非文本框）：禁止 activate / makeKey。
    static var shouldStealFocusOnPlainIslandMouseDown: Bool { false }
}
