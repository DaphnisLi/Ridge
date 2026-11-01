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

## 3. 声音（控制台混音台组件）

- [x] 输出设备列表 / 切换默认输出、系统主音量（过滤虚拟/聚合设备）
- [x] 按 App 输出活跃列表与独立音量（macOS 14.2+ Process Tap；需屏幕录制；失败 fail-open）
- [x] 控制台岛 UI：混音台（无独立设置页；选项挂在控制台设置）
- [ ] 默认输出设备偏好记忆

## 4. 项目释放（控制台模块）

- [x] 用户指定根目录扫描 package.json / Cargo.toml / go.mod 等
- [x] 进程 / 端口（lsof）/ Docker 按项目聚合，展示 CPU·内存
- [x] 一键释放：SIGINT → 2s → SIGKILL；未归属端口只读
- [x] Watch 进程结束：展开岛 + 系统通知
- [ ] 电量 / Energy Impact 精确读数（当前以 CPU·内存代替）

## 5. 货架 + 剪贴板历史（控制台模块）

- [x] Shelf：拖文件 / 图片 / 文件夹到岛暂存（路径存内存）；点按 Finder 显示；可拖出
- [x] 剪贴板历史：轮询 NSPasteboard；Tab 分文本 / 链接 / 颜色 / 图片 / 截图
- [x] 点历史条目写回系统剪贴板
- [x] 私密过滤：前台为 1Password 等密码管理器时不记录
- [x] 控制台模块开关；与混音台 / 项目释放同页分段切换

## 6. 媒体 Now Playing（内容型小组件）

- [x] `builtin.media`：封面 / 标题 / 艺术家 / 进度条 / 上一曲·播放暂停·下一曲·随机·循环；进度拖拽 seek
- [x] 有 Now Playing 会话时上岛（播放或暂停），清空后撤回；与会议组件同为「有内容才显示」
- [x] `MediaRemoteAdapter`（perl 桥）读取 macOS 15.4+ / 27 Now Playing；Apple Music、Spotify、播客、浏览器网页媒体
- [ ] 浏览器扩展增强（非系统 Now Playing 场景）

## 后续（未开始）

- 系统状态 widget（控制台读数）
- AI / 用户自定义 widget 加载器
