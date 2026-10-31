# Ridge 实现进度

## 1. 灵动岛窗口本体与动画（地基）

- [x] NSPanel 无边框浮层：`floating` 以上 level、不进 Dock / ⌘Tab（`LSUIElement` + `.accessory`）
- [x] 刘海对齐：`safeAreaInsets.top` + `auxiliaryTopLeft/RightArea` 推算真实宽度
- [x] 点击穿透：收起时 `ignoresMouseEvents` 按指针切换
- [x] 全屏自动隐藏、悬停展开、设置大窗、展开尺寸 / 圆角 / 震感等
- [ ] ProMotion 120Hz 专项压测与曲线微调
- [ ] 外接屏切换时的过渡动画打磨
- [ ] 菜单栏下方胶囊样式

## 2. 小组件架构（地基）

扩展契约（内置 / 用户 / AI 共用）：

- [x] `WidgetManifest`：id、名称、摘要、版本、`source`（builtin/user/generated）、`kind`
- [x] `WidgetContext`：`requestDisplay` / `withdrawDisplay` / `openSettings` / 隔离 storageKey（禁止直连 Runtime）
- [x] `IslandWidget` 协议 + `WidgetModule` / `TypedWidgetModule` 注册单元
- [x] `WidgetRegistry`：`register` / `unregister`，预留热加载
- [x] `WidgetRuntime`：优先级 + 时间戳调度；pin 常驻；未 pin 按需销毁
- [x] 系统空态岛 `system.empty`：无内容争夺时展示引导文案与「去添加小组件」
- [x] 设置：库内开关、拖拽排序（右侧手柄）、常驻；空态不进列表
- [ ] 点击展开 / 点空白收起（可配置）
- [ ] 采样类 widget 可配置刷新频率
- [ ] 用户包 / AI 生成包校验与热加载落地

新增内容型小组件步骤：实现 `IslandWidget` → `registry.register(TypedWidgetModule<YourWidget>())` → 在 `requestDisplay` 时争夺展示。

## 后续（未开始）

- 媒体 Now Playing widget
- 日历 / 会议倒计时 widget
- 系统状态 widget
- AI / 用户自定义 widget 加载器
