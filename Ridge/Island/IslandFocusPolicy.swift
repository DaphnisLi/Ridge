import Foundation

/// 岛窗焦点策略：浮层不得长期抢走其它 App 的键盘 / 前台。
///
/// 固定布尔来自 `LockedInvariants.Focus`（未授权禁止改锁定文件）。
enum IslandFocusPolicy {
    /// 指针进入可点区、仅关闭穿透时：不要抢前台。
    static var shouldActivateAppWhenDisablingClickThrough: Bool {
        LockedInvariants.Focus.shouldActivateAppWhenDisablingClickThrough
    }

    /// 展开岛（悬停 / 通知等）：默认不抢前台；文本输入路径自行 `IslandInteractionFocus.prepare`。
    static var shouldActivateAppOnExpand: Bool {
        LockedInvariants.Focus.shouldActivateAppOnExpand
    }

    /// 开启整窗穿透时：必须交出 key，并允许降回 accessory。
    static var shouldResignKeyWhenEnablingClickThrough: Bool {
        LockedInvariants.Focus.shouldResignKeyWhenEnablingClickThrough
    }

    /// 普通岛上 mouseDown：禁止 `NSApp.activate`（会粘住键盘）。
    static var shouldActivateAppOnPlainIslandMouseDown: Bool {
        LockedInvariants.Focus.shouldActivateAppOnPlainIslandMouseDown
    }

    /// 普通岛上 mouseDown：需要 `makeKey`，否则 SwiftUI Button 不吃这次点击。
    static var shouldMakeKeyOnPlainIslandMouseDown: Bool {
        LockedInvariants.Focus.shouldMakeKeyOnPlainIslandMouseDown
    }
}
