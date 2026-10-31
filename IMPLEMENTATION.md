# Ridge 实现进度

## 1. 灵动岛窗口本体与动画（地基）

- [x] NSPanel 无边框浮层：`floating` 以上 level、不进 Dock / ⌘Tab（`LSUIElement` + `.accessory`）
- [x] 刘海对齐：`safeAreaInsets.top` + `auxiliaryTopLeft/RightArea` 推算真实宽度
- [x] 点击穿透：`IslandHitTestView.hitTest` 仅在可交互框内命中
- [x] 全屏自动隐藏：Space / 前台 App 变化 + 窗口列表尺寸检测
- [x] 常驻态贴合刘海（约 0.96×）；展开宽×2、高×3
- [x] 窗口固定展开尺寸 + 屏幕坐标轮询悬停（避免抖动）
- [x] Spring 动画：`response 0.35 / speed`，`dampingFraction 0.8`
- [x] 悬停自动展开 / 移开收起（无手动展开菜单）
- [x] 无刘海屏：隐藏岛窗口，保留菜单栏入口
- [x] 设置大窗：侧边栏 + 白底内容，当前屏居中
- [x] 岛设置：动画速度、下圆角、震感、全屏禁用（录屏/多屏样式入口已收起）
- [ ] ProMotion 120Hz 专项压测与曲线微调
- [ ] 外接屏切换时的过渡动画打磨
- [ ] 菜单栏下方胶囊样式

## 后续（未开始）

- 媒体 Now Playing
- 日历 / 会议倒计时
- 系统状态 widget
