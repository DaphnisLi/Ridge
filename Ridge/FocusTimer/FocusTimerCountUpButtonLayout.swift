import AppKit
import Foundation

/// 选时「正计时」绿胶囊布局契约（可单测）。
/// 反复回归：宽度写死右侧大片空白；点「正计时」三字无反应（热区缩成图标）。
enum FocusTimerCountUpButtonLayout {
    static let height: CGFloat = 26
    static let horizontalPadding: CGFloat = 10
    static let iconSide: CGFloat = 14
    static let iconTitleGap: CGFloat = 5
    /// 曾误用的写死宽；自适应结果必须明显更窄，禁止再回到此档。
    static let forbiddenFixedWidth: CGFloat = 88

    static var titleFont: NSFont {
        NSFont.systemFont(ofSize: 12, weight: .semibold)
    }

    /// 图标起点（左内边距后）。
    static var iconMinX: CGFloat { horizontalPadding }

    /// 文案区起点（图标 + 间距之后）——「正计时」三字从此开始。
    static var titleMinX: CGFloat {
        horizontalPadding + iconSide + iconTitleGap
    }

    static func titleWidth(_ title: String, font: NSFont = titleFont) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// 内容自适应宽：左右等宽 padding，无右侧虚空。
    static func fittingWidth(title: String, font: NSFont = titleFont) -> CGFloat {
        ceil(
            horizontalPadding * 2
                + iconSide
                + iconTitleGap
                + titleWidth(title, font: font)
        )
    }

    static func fittingSize(title: String, font: NSFont = titleFont) -> CGSize {
        CGSize(width: fittingWidth(title: title, font: font), height: height)
    }

    /// 本地坐标是否落在整颗胶囊内（图标 + 文案 + 内边距）。
    static func containsTap(localX: CGFloat, title: String) -> Bool {
        let width = fittingWidth(title: title)
        return localX >= 0 && localX < width
    }

    /// 本地坐标是否落在「正计时」文案带（不含左侧图标）。点三字必须算命中。
    static func containsTitleTap(localX: CGFloat, title: String) -> Bool {
        let width = fittingWidth(title: title)
        let titleEnd = width - horizontalPadding
        return localX >= titleMinX && localX < titleEnd
    }
}

/// 播放媒体 vs 专注选时：纯函数闸门，供 `MediaCompactPresence` 与单测共用。
enum MediaFocusPickingGate {
    /// 专注选时页打开时，禁止播放悬停/按住抢成媒体大面板。
    static func shouldBlockMediaExpand(
        focusPhase: FocusTimerPhase,
        activePageID: String?
    ) -> Bool {
        focusPhase == .picking && activePageID == FocusTimerWidget.manifest.id
    }
}
