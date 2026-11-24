import CoreGraphics

/// 播放收起待命视觉令牌（可单测锁定）。
/// 改间距 / 封面边长须用户明确要求，并同步 `test_uiStyleLock_mediaCompactStandby`。
enum MediaCompactStandbyMetrics {
    /// 左翼封面边长；专注环须同档（见 `FocusTimerCompactMetrics.progressRingDiameter`）。
    static let artworkSide: CGFloat = 22
    /// 封面 ↔ 歌名。
    static let leftClusterSpacing: CGFloat = 8
    /// 满岛右翼：律动条 ↔ 时长（曾 6 过挤；禁再随意改）。
    static let equalizerElapsedSpacing: CGFloat = 12
    /// 满岛歌名 / 时长字号。
    static let titleFontSize: CGFloat = 12
    static let elapsedFontSize: CGFloat = 13
    /// 双槽半块音符图标字号。
    static let wingNoteFontSize: CGFloat = 15
}
