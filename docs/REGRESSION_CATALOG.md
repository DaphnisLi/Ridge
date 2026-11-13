# Ridge 回归问题目录

本文档记录开发中出现的缺陷与易复发模式，供 Agent 维护，并作为后续**自动化测试**的优先清单。

## 约定

| 项 | 说明 |
|---|---|
| 收录时机 | 修完或用户明确指出后写入；同一根因再出现 → `occurrences` +1 |
| **重复出现** | `occurrences ≥ 2`，须标 `recurring: true`，并列入下方「重复出现问题」表 |
| 自动化（强制） | **仅** `recurring: true`：须有 `RidgeTests` 锚定用例；改完代码跑 `./scripts/test-recurring.sh` |
| 自动化（不强制） | `occurrences == 1`：**不必**写测、**不必**每次改代码后跑 |
| Manifest | `RidgeTests/RecurringRegressionManifest.swift` 与下表 id 同步；覆盖闸门见 `RecurringRegressionCoverageTests` |
| 权威规则 | `.cursor/rules/regression-catalog.mdc` |

---

## 重复出现问题（occurrences ≥ 2）

| id | 标题 | 次数 | 症状 | 防护 / 测试锚点 |
|---|---|---|---|---|
| `island-hover-retention` | 岛悬停热区退化 | ≥8 | 展开后热区缩成刘海/短 tip；下移/拖/列表纵滑一半就收岛；**非拖文件却认大接近区** | 收起悬停仅刘海；拖文件才用接近区；展开地板 + 中下点用例 |
| `island-chrome-double-padding` | 岛边距叠两层 | ≥3 | 内容根再加 padding / tip 误用大底距；左右底边距应变固定令牌 | `IslandChrome.insets`；`RegressionCatalogTests.test_islandChromeDoublePadding_*` |
| `settings-preview-live-data` | 设置预览用真数据 | ≥2 | 库卡/详情拉实时源；空数据/网络抖时预览难看 | `test_settingsPreviewLiveData_*`：媒体/会议/电量假样张非空 + 股票固定两卡 |
| `shelf-copied-notice-miss` | 复制成功提示看不见 / 闪一下就没 | ≥6 | 取色/框选后看不见；关货架不上岛；或展开未完即 hoverEnd 收掉 | `ClipboardCopiedNoticeGate`；`copy.*` keepExpanded；翼→短放行；`test_shelfCopiedNoticeMiss_*` |
| `tip-outline-panel` | tip 上角圆/直角反复改 | ≥2 | 会议等 tip 上角与贴顶直角期望不一致 | 真岛/预览一律 `.panel`；`test_islandOutline_panelKeepsSquareTopCorners` |
| `island-focus-steal` | 岛抢焦点 / 矫枉按钮失灵 | ≥5 | 粘键盘；SwiftUI 首击无响应（会议入会 / 媒体暂停切歌 / 混音台滑条静音） | 普通点击只 makeKey；穿透 resignKey；岛内操作钮用 AppKit；`test_islandFocusPolicy_*` |
| `library-island-stage-stretch` | 库卡/详情预览黑岛被拉高留空 | 4 | 黑岛过高；电量空黑；番茄 minStageHeight / 环 24+预览垫高 | 环=媒体封面 22；预览上下 6；`test_compactIsland_*` |
| `settings-preview-island-appearance` | 设置预览比真岛暗淡 | 2 | 文字/外设卡发闷；曾误画分页角点 | 禁预览 `.disabled`；深色+sRGB；`test_settingsPreviewIslandAppearance_*` |
| `shelf-magnetic-staging-double` | 磁吸双舱用完又冒一次 | ≥2 | 投放后双舱再闪；**未入舱松手后岛回头再开** | `fileDragCanceled` 强收 + 悬停冷却；双舱须 `fileDrag`；`test_shelfFileDragCancel_*` |

---

## 已记录问题（全量）

### island-hover-retention — 岛悬停热区退化

- **recurring:** true  
- **occurrences:** 8+（历史反复；2026-11-09 tip 污染 lastStable；2026-11-10 纵滑误收；2026-11-11 收起播放小岛两翼；2026-11-13 展开后下移一半仍收；**2026-11-13 非拖文件也认过大接近区**）  
- **症状:** 大岛仍在，保展开/可点区退成刘海或 tip 小框；下移一半就收岛；短通知像「小岛盖住大岛」；控制台列表滚一半误收；**普通移入在刘海外很远就被「识别」展开**  
- **根因倾向:** Preference 误报矮框；热区只用 `notchFrame`；瞬时短条写入 `lastStable`；纵滑无左键；**收起态悬停跟宽小岛/接近区走**；展开瞬间矮 Preference  
- **防护:** 收起悬停展开 **仅刘海**（`hoverExpandFrame`）；`fileDragApproachFrame` **仅**拖文件；展开态仍用大面板保展开 + `expandedRetentionFloor`；`scrollHold`  
- **自动化:** `test_islandHoverRetention_*` + `test_islandHoverExpand_collapsedOnlyNotchCountsWithoutFileDrag` + `test_islandHoverExpand_fileDragApproachZoneOnlyWhenDraggingFiles`  
- **曾缺口（已补 2026-11-13）:** Preference 未到 / 误报矮框；非拖文件误用大接近区。  
- **日志锚点:** `指针离开保展开区，安排收起`；`货架拖入：钉住展开`（须 `fileDrag=true`）；`保展开改用稳定面板尺寸`

### island-chrome-double-padding — 岛边距叠两层

- **recurring:** true  
- **occurrences:** 3+（通知卡 / 多 widget 反复翻车；**2026-11-10 会前提示 tip 根上再叠 nudge，左右底距偏大**）  
- **症状:** 下边距过大，左右离岛边过宽，或 tip 误用展开页大底距  
- **根因倾向:** 根视图 `.padding(.vertical/.horizontal)` / HTML `px/py` / 翼 tip `nudgeInward` 再叠 `IslandChrome`；或未标 `usesNotchWingChrome` 退回 `contentBottom`  
- **防护:** 左右/底只走 `IslandChrome.insets(for:)`；widget/通知卡根视图只排内容；会议 tip 禁根上外圈 padding  
- **自动化:** `RegressionCatalogTests.test_islandChromeDoublePadding_*`（令牌固定值 + 各 surface 左右/底 inset + `meetingLead` 须 wing chrome）

### settings-preview-live-data — 设置预览用真数据

- **recurring:** true  
- **occurrences:** 2（股票库卡多卡真价感；此前其它 widget 同类）  
- **症状:** 无数据/网络失败时预览空或「更新中」；库卡裁切多卡  
- **根因倾向:** 预览直连 Session / 实时源；样张塞满多枚  
- **防护:** `WidgetSamplePreview.island` / `SettingsIslandPreviewCard`；假数据固定形态（股票两卡样张）  
- **自动化:** `test_settingsPreviewLiveData_stockSampleUsesFixedFakePair`、`test_settingsPreviewLiveData_widgetSamplePreviewUsesFakeSamples`（媒体/会议标题非空、电量 hugs + opaque）

### library-island-stage-stretch — 库卡/详情预览黑岛被拉高留空

- **recurring:** true  
- **occurrences:** 4（2026-11-09 股票；2026-11-11 电量；2026-11-12 minStageHeight；**同日专注左环 24 + 库卡 vertical 8/minHeight 44，仍比媒体小岛高**）  
- **症状:** 库卡/详情预览黑岛呈过高矩形；股票卡被撑高；电量样张卡片贴顶、下半截空黑；番茄待命黑岛比内容高一截  
- **根因倾向:** 对岛施 `maxHeight: .infinity` / 写死双行高；样张行数与占位高度不一致；**`hugsContent: false` 时把 `minStageHeight` 写在岛 frame 上**；进度环大于媒体封面、预览垫高不一致  
- **防护:** 库卡岛 `.fixedSize(vertical: true)`；窄 widget `hugsContent`；`batterySample` 按单行样张高度；固定预览宽时高度仍 hugs；**`FocusTimerCompactMetrics` 环 22、预览上下 6 / minHeight 36 对齐媒体**  
- **相关代码:** `FocusTimerCompactMetrics`、`WidgetSamplePreview.focusTimerSample`、`SettingsIslandStage.stageCanvas`  
- **自动化:** `RegressionCatalogTests.test_libraryIslandStageStretch_*`、`test_settingsPreviewTipForcedStretch_*`、`test_compactIsland_sharedHeightAndMediaWidth`

### settings-preview-tip-forced-stretch — tip 预览被强制拉宽撑开左右间距

- **recurring:** false（首次；与 chrome 定死约定相关，易再发）  
- **occurrences:** 1（2026-11-12：统一 tip/媒体/番茄预览宽时把 tip `hugsContent` 关成 false 并强制库卡 360）  
- **症状:** 设置里会议/额度/久坐/取色/框选/外设 tip 预览左右黑边变大，翼内容被拉散；本应贴合固有宽  
- **根因倾向:** tip 翼宽与 `IslandChrome.contentHorizontal` 是定值，却套 `maxIslandWidth` + `hugsContent: false` / `libraryIslandWidth` 把黑岛拉满  
- **防护:** `tipPreviewHugsContent == true`；tip id 不得进 `libraryIslandWidth`；详情 `hugsContent` 走 `tipPreviewHugsContent`；`maxIslandWidth: tip` 仅作上限  
- **相关代码:** `WidgetSamplePreview.libraryIslandWidth` / `tipPreviewHugsContent`、各 tip SettingsPane  
- **自动化:** `RegressionCatalogTests.test_settingsPreviewTipForcedStretch_*`

### settings-preview-island-appearance — 设置预览文字/卡片色与真岛不一致

- **recurring:** true  
- **occurrences:** 2（2026-11-12：角点/浅色窗发灰；**同日再发：样张仍比真岛暗一截——预览路径 `.disabled(true)` 整卡降透明度**）  
- **症状:** 库卡/详情黑岛内文字与设备卡片明显比真岛暗淡；样张左右上角曾出现分页角点  
- **根因倾向:** ① 预览 `Button.disabled` 系统降透明度；② 浅色设置窗 + `calibratedWhite` 抬灰；③ 误画 `pageDot`  
- **防护:** 预览用 `allowsHitTesting(false)`，**禁止** `.disabled`；`.preferredColorScheme(.dark)`；卡片色 sRGB；**禁止**样张分页角点  
- **相关代码:** `BatteryDeckView.deviceCard`、`BatteryDeckIslandPreview`、`WidgetIslandPreviewShell`  
- **自动化:** `RegressionCatalogTests.test_settingsPreviewIslandAppearance_*`

### shelf-magnetic-staging-double — 磁吸双舱 / 拖文件松手后又开

- **recurring:** true  
- **occurrences:** 2+（2026-11-13：投放后双舱再闪；**同日未入舱松手后岛回头再开**）  
- **症状:** 拖文件出双舱后入舱/隔空完成再闪一次；或拖近展开后**未放暂存区就松手**，岛收起后又自动打开  
- **根因倾向:** ① `isTargeted` 滞后再 `setActive(true)`；② 拖文件 `shelfDropApproach` 展开后松手仍 `retention=true`（大面板）不收；③ 松手后普通悬停立刻再 expand  
- **防护:** `endAfterDrop` 冷却；双舱须 `fileDrag`；**未入舱松手 `fileDragCanceled` 强收 + `postFileDragHoverSuppress`**；收起悬停仅刘海，接近区仅拖文件  
- **自动化:** `test_shelfMagneticStagingDouble_*`、`test_shelfFileDragCancel_*`、`test_islandHoverExpand_*`

### shelf-copied-notice-miss — 复制成功有时不上岛提示

- **recurring:** true  
- **occurrences:** 6（2026-11-08 偶发；2026-11-09 取色两次；2026-11-10 翼 tip；2026-11-11 货架开关；**2026-11-11 展开未完即消失：`keepsExpandedWithoutHover` 未开，hoverEnd 秒收**）  
- **症状:** 复制文字/链接/颜色/截图后不出现「已复制」；取色/框选后尤甚；tip 开着但货架关时 Cmd+C 也不上岛；**或刚展开就收起、几乎看不清**  
- **根因倾向:** ① dismiss 后再 present 会先收岛；② 翼→短/圆岛 Preference 缩宽被误缩守卫拒绝；③ `showCopiedNotice` 关；④ 剪贴板轮询只跟货架模块走；⑤ **`copy.*` 未 `keepsExpandedWithoutHover`，指针不在岛上时 0.1s 后 hoverEnd 收岛**  
- **防护:** `ClipboardCopiedNoticeGate.syncClipboardMonitoring`；**`prepareNotchRightOrbLayout`（Ø32 圆岛）**；翼→圆岛放行；**`copy.*` 保持展开至约 3s 自动收起**；clamp 不得把 Ø32 抬到刘海宽  
- **相关代码:** `ClipboardCopiedNoticeGate`、`IslandNoticePayload.usesNotchRightOrbChrome`、`IslandExpandedPanelPolicy`、`ClipboardCopiedIslandView`  
- **自动化:** `RegressionCatalogTests.test_shelfCopiedNoticeMiss_*`（含 tip 开/货架关、copy 须 keepExpanded + 圆岛尺寸）、`IslandExpandedPanelPolicyTests`

### stocks-refresh-stuck-querying — 行情失败仍显示「正在查询」

- **recurring:** false（同类状态机问题可能再现）  
- **occurrences:** 1（会话内集中修过）  
- **症状:** `isRefreshing` 卡住或失败无缓存时假死在「正在查询」  
- **防护:** 取消时清状态；失败保留缓存；多源兜底  
- **自动化建议:** 取消/失败路径后 `isRefreshing == false`；有缓存时展示 stale 而非 updating

### custom-dnd-reorder-quality — 手写拖拽排序质量差

- **recurring:** false  
- **occurrences:** 1  
- **症状:** 只拖手柄图标、交换而非插入  
- **防护:** 设置列表优先 `List` + `onMove`  
- **自动化建议:** `move(fromOffsets:toOffset:)` 顺序断言

### ai-usage-account-scope-tips — AI 额度提示须账号+周期额度双判

- **recurring:** false  
- **occurrences:** 1（2026-11-08：用户反馈从未提示；实际为剩余常高于充裕线，且换回旧号被同档去重挡住）  
- **症状:** 频繁换 Cursor 账号时看不到岛上额度提示  
- **根因倾向:** 仅剩余 ≤ 充裕阈值才弹；换号依赖用量轮询偏慢；同作用域同档记忆挡住「换回再提示」  
- **防护:** 提示作用域 = 账号 + 计费周期；15s 嗅探本机邮箱加速换号；换作用域且已在触发带则必弹  
- **自动化建议:** 模拟换 `accountID` 且 remaining 落在警戒带 → 必 present；同账号未跌破线 → 不重复弹

### shelf-color-pick-external-tool-stuck — 取色后岛永久穿透假死

- **recurring:** false（历史 ColorSampler 残留卡鼠标同类；2026-11-09 整 App「卡死」）  
- **occurrences:** 1  
- **症状:** 点货架吸管后岛/菜单栏看似卡死；日志停在 `colorPickTip` 已上岛，无取色完成/取消；后台 `projects-last` / AIUsage 仍可能写  
- **根因倾向:** `beginExternalPointerTool` 后 tip `expand` 调 `ensureIslandInteractionReady` 抢前台，掐死 `NSColorSampler` 会话 → 完成回调永不来 → `isExternalPointerToolActive` 永久 true → 整窗点击穿透  
- **防护:** 外部指针工具中 expand / ensure 跳过抢前台；先 `sampler.show` 再 present tip；Esc 监听 + 30s 超时强制 `finishColorPick(nil)`；关键路径 warn 落盘  
- **相关代码:** `ShelfCaptureTools`、`IslandController.beginExternalPointerTool` / `expand` / `ensureIslandInteractionReady`  
- **自动化建议:** 外部工具态下 expand 不得调用 `IslandInteractionFocus.prepare`；模拟 sampler 无回调超时后 `isExternalPointerToolActive == false`

### battery-continuity-iphone-missing — Continuity 手机不上电量列表

- **recurring:** false  
- **occurrences:** 1（2026-11-10：附近 iPhone 广播可见但加密超时后整卡消失）  
- **症状:** 控制中心能看手机电量，Ridge 电量页没有 iPhone  
- **根因倾向:** ① 只在读到 Battery Service 后才建卡，连接/加密失败则无条目；② 广播刷新 `lastSeen` 误当重试冷却，加密失败后不再重连；③ Continuity 路径 info 日志不落盘，难排查  
- **防护:** 发现即 upsert（percent 可 nil）；`continuityLastAttemptAt` 与 lastSeen 解耦；关键路径 `AppLog.warn`；蓝牙 denied 时明确 warn  
- **相关代码:** `BatteryCoreBluetoothMonitor`  
- **自动化建议:** 模拟 didDiscover + didFailToConnect 后 `continuityDevices` 仍含该 UUID；冷却后应再次 connect

### settings-close-blocked-by-island — 设置窗关不掉 / 假死

- **recurring:** false  
- **occurrences:** 1（2026-11-10）  
- **症状:** 设置有时点红灯关不了，整窗像卡死；岛盖在标题栏上  
- **根因倾向:** 岛窗 level 高于设置；穿透依赖 `isSettingsSessionActive`，开窗异步开会话 / 关窗先清会话再 orderOut → 红灯点击被岛吞；OCR/货架抬到 screenSaver/popUpMenu 时更重  
- **防护:** `isSettingsPresented` 先于 orderFront、关窗先清标记并 orderOut；命中设置用 presented 而非 session；开/关设置强制 resting + click-through；设置展示中禁止抬层  
- **相关代码:** `MenuBarController`、`IslandController.pollPointer`、`IslandWindow.sendEvent`  
- **自动化建议:** 设置 presented 且鼠标在设置 frame 内时 `ignoresMouseEvents == true`；windowShouldClose 后 `isSettingsPresented == false`

### island-family-presence — 提示/实况/面板上岛与悬停展开

- **recurring:** false  
- **occurrences:** 1（2026-11-10 产品规则落地）  
- **症状:** 提示类常驻分页；实况开启即占岛；无面板时悬停仍展开空岛  
- **根因倾向:** `WidgetLibraryFamily` 仅用于设置分段，Runtime 未按 family 闸门；`enabledPanes` 含电量即进分页；hover 无条件 expand  
- **防护:** tip 禁 `requestDisplay`；live 须 `LiveIslandGate.open`；panel 直接上岛；`allowsHoverExpand` 无面板/未点进实况时拒绝 hover；**库页 UI 已扁平不分段**，闸门仍用 family；默认序见 `WidgetLibraryLayout`  
- **相关代码:** `LiveIslandGate`、`WidgetRuntime.buildVisiblePages` / `allowsHoverExpand`、`IslandController.pollPointer`、`WidgetLibraryLayout`  
- **自动化:** `RegressionCatalogTests.test_widgetLibraryFamily_*` + `test_widgetLibraryLayout_flatDefaultOrder`

### controldeck-init-battery-reentrancy — 控制台 init 重入启动崩

- **recurring:** false  
- **occurrences:** 1（2026-11-10：打开 App 立即退出，菜单栏无图标）  
- **症状:** `open Ridge` 后无进程；崩溃 `BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively`  
- **根因倾向:** `WidgetSettings` → `ControlDeckSettings.init` 同步 `BatterySession.start` → `refreshLiveInvite` 再取 `ControlDeckSettings.shared`，`dispatch_once` 重入  
- **防护:** ControlDeck init 内模块 `start()` 改为 `Task { @MainActor in … }` 延后到 shared 完成后再跑  
- **相关代码:** `ControlDeckSettings.init`、`BatterySession.refreshLiveInvite`  
- **自动化建议:** 单测/冒烟：构造 `ControlDeckSettings.shared` 且 battery 模块已开时不得同步回访 shared

### island-focus-steal — 岛抢鼠标/键盘焦点

- **recurring:** true  
- **occurrences:** 5（抢焦点；矫枉后按钮失灵；翼 tip 可点区过窄点穿；2026-11-12 媒体展开暂停/切歌；**2026-11-13 混音台滑条/静音/设备行 SwiftUI 无响应**）  
- **症状:** 悬停或点过岛后其它 App 点不进；或会议「进入」/媒体播放控件/混音台控件点了没反应  
- **根因倾向:** 一律 `activate`；去掉 `makeKey`；`hosting` 吞掉 SwiftUI 首击；横滑翻页 pan 抢走音量横向拖动；会议 tip 可点区停在刘海/短条  
- **防护:** 普通点击只 `makeKey`；穿透即 resign；`hitTest` 直达 `NSControl` / `IslandDirectHitTarget`；会议 tip / 媒体播放 / **混音台滑条·静音·设备行**用 AppKit；翻页 pan 在控件上 `failed`  
- **相关代码:** `IslandFocusPolicy`、`IslandDirectHitTarget`、`MixerVolumeTrackNSView`、`MixerMuteNSButton`、`MediaTransportAppKitButton`、`MeetingLeadAppKitPillButton`  
- **自动化:** `RegressionCatalogTests.test_islandFocusPolicy_*`、`test_controlDeckVolumeHeight_adaptsBelowMaxAndCapsAtMax`

### tip-outline-panel — 瞬时提示上直角下圆角

- **recurring:** true  
- **occurrences:** 2（2026-11-10：先改四角等弧，后改回上直角）  
- **症状:** tip 上角圆/直角与产品期望反复不一致  
- **根因倾向:** tip 外形在 `.capsule` / `.panel` 间摇摆  
- **防护:** 真岛与设置预览一律 `IslandOutlineStyle.panel`（左上/右上直角、下圆角）  
- **相关代码:** `IslandContentView.outlineStyle`、`WidgetSamplePreview.outlineStyle(for:)`、各 tip 配置页  
- **自动化:** `RegressionCatalogTests.test_islandOutline_panelKeepsSquareTopCorners`

### meeting-tip-advance-next — 第一场关掉后不提示第二场

- **recurring:** false  
- **occurrences:** 1（2026-11-10：背靠背会议，第一场开始后保留结束无第二场 tip）  
- **症状:** 关闭/过期第一场会前提示后，即使第二场已在 lead 窗口内也不上岛  
- **根因倾向:** 日历只暴露 `nextMeeting`（仍进行中的第一场）；widget 在 grace 过期后提前 return，从不改选下一场  
- **防护:** `upcomingMeetings` 列表 + `MeetingLeadTipSelector`；grace/入会后 `onTipExpired` / `joinedAdvance` 立刻 reevaluate  
- **相关代码:** `MeetingCalendarService`、`MeetingLeadTipSelector`、`MeetingCountdownWidget`、`MeetingLeadSession`  
- **自动化:** `RegressionCatalogTests.test_meetingTipAdvanceNext_*`

### meeting-tip-preemption — 其它瞬时提示盖住会前提示

- **recurring:** false  
- **occurrences:** 1（2026-11-10：产品要求会议 tip 优先级最高）  
- **症状:** 复制成功 / 取色 / 电量等后到的瞬时条把会前提示顶掉  
- **根因倾向:** `IslandNoticeCenter.present` 一律后到覆盖，无抢占优先级  
- **防护:** `IslandNoticePayload.preemptionRank`；会议=100，其它=0；`IslandNoticePreemption.shouldAccept` 挡住低优先级  
- **相关代码:** `IslandNoticeCenter`、`IslandNoticePreemption`  
- **自动化:** `RegressionCatalogTests.test_meetingTipPreemption_*`

### live-invite-removed — 去掉电量/媒体「打开」邀请 tip

- **recurring:** false  
- **occurrences:** 1（2026-11-10：产品要求去掉实况邀请条）  
- **症状:** 外设电量 / 正在播放先冒「打开」tip，盖住或打断会前提示  
- **根因倾向:** `LiveIslandGate` 先 tip 再点进；Battery/Media 持续 `present(.liveInvite)`  
- **防护:** 电量有设备时 `admit` 准入；媒体改为播放小岛常驻、点按才 `open` 大面板（见 `media-compact-not-resident`）；`liveInvite` 已删；低电/满电/接入走 `builtin.peripheralTip`  
- **相关代码:** `LiveIslandGate.admit`、`BatterySession.refreshLivePresence`、`MediaNowPlayingWidget`、`PeripheralTipWidget`  
- **自动化:** `RegressionCatalogTests.test_liveInviteRemoved_admitAllowsContentPage`

### media-compact-not-resident — 播放大面板不得常驻分页

- **recurring:** false  
- **occurrences:** 1（2026-11-11：产品纠正「收起待命」命名与常驻逻辑；同日改为悬停展开）  
- **症状:** 有曲目即 admit/自动 expand，大面板占分页；设置预览误称「收起待命」  
- **根因倾向:** `MediaNowPlayingWidget` 有曲目即 `admit`+`revealPage`+`expand`；与「仅小岛常驻」不符  
- **防护:** 有曲目不自动 admit；收起态正显示播放小岛时悬停才 `open`；会议 tip 等盖住/展开时不打开媒体大面板；收岛 `close` 撤争夺；预览左「正在播放」右「展开播放」  
- **相关代码:** `MediaNowPlayingWidget`、`MediaCompactPresence.isVisiblyShowingCompact`、`LiveIslandGate`、`IslandController`、`MediaSettingsPane`  
- **自动化:** `RegressionCatalogTests.test_mediaCompactNotResident_gateClosedUntilOpen`

### sound-app-volume-host-key — 按 App 音量对不上宿主进程

- **recurring:** false  
- **occurrences:** 1（2026-11-13：汽水音乐 / iPhone 镜像滑条无实际音量变化）  
- **症状:** 混音台能列出正在播放的 App，拖滑条 / 静音听感不变  
- **根因倾向:** UI 行按宿主 bundle 聚合，`applyRoute` 却用进程自身 `bundleID == key` 过滤；Helper 空匹配后静默 return；滚动区 `compositingGroup` 亦可能吞 AppKit 滑条命中  
- **防护:** `SoundProcessMonitor.processObjectIDs(forHostKey:)` 与聚合同 key；混音台滚动关 compositing；关键路径 warn 落盘  
- **相关代码:** `SoundSession.applyRoute`、`SoundProcessMonitor.hostKey`、`AlwaysVisibleScrollView.usesCompositingGroup`  
- **自动化:** `RegressionCatalogTests.test_soundAppVolumeHostKey_helperBundleDoesNotEqualHostKey`

---

## 变更日志

| 日期 | 变更 |
|---|---|
| 2026-11-13 | recurring 全量闸门：`RecurringRegressionManifest` + `scripts/test-recurring.sh`；occurrences=1 不强制测 |
| 2026-11-13 | 按 App 音量：宿主 key 匹配 Process Tap；混音台滚动关 compositing；catalog `sound-app-volume-host-key` |
| 2026-11-12 | 库卡灰舞台三族统一 106；详情 tip/待命 `tipStageMinHeight` 88 |
| 2026-11-12 | 媒体/专注待命预览与会议 tip 同 290×30 + chrome（`meetingMatchedCompactChrome`） |
| 2026-11-12 | 媒体/番茄预览直接按 290 排（禁 scale），上下垫 8 / minH 42，避免字与岛高被压 |
| 2026-11-12 | 预览黑岛目标宽改 290（「已复制」除外）；库卡+详情统一缩放 |
| 2026-11-12 | 库卡+详情舞台黑岛一律同比缩到 360；媒体/番茄先 380、控制台先满宽再缩 |
| 2026-11-12 | 库卡黑岛一律同比缩到 360（`LibraryIslandPreviewScaleModifier`），灰舞台不缩 |
| 2026-11-12 | 电量库卡黑岛同比缩到 library 宽（`BatteryDeckIslandPreview.libraryPreviewScale`），灰舞台不缩 |
| 2026-11-12 | 实况/面板库卡改提示同款灰舞台+底栏（`WidgetLibraryCardLayout`） |
| 2026-11-12 | 专注待命环 22 + 预览边距对齐媒体小岛；`FocusTimerCompactMetrics`；stretch +1 |
| 2026-11-12 | 媒体展开：立刻套用 `MediaExpandedContentSize` 抬高可点区；播放钮 AppKit 锁正圆（曾椭圆+底栏点空） |
| 2026-11-13 | 未入舱松手强收改为「离开大岛保展开区」才收，大岛内松手不收；补 expanded≠approach 测试 |
| 2026-11-13 | 磁吸开关不改拖文件接近区（宽=刘海、高≥3×刘海）；只关双舱/隔空；文案同步 |
| 2026-11-13 | 拖文件接近区：宽=刘海、高≥3×刘海高（向下）；普通移入仍仅刘海 |
| 2026-11-13 | 未入舱松手强收 + 悬停冷却，防拖文件后回头再开；严格 `test_shelfFileDragCancel_*` |
| 2026-11-13 | 拖文件接近区改为刘海外扩，不再用控制台 660×300 当地基 |
| 2026-11-13 | 收起态悬停展开仅刘海；控制台大接近区只在拖文件时生效；`test_islandHoverExpand_*` |
| 2026-11-13 | 磁吸双舱「用完又冒一次」：`endAfterDrop` 冷却 + 双舱须 fileDrag；关键路径改 warn 落盘 |
| 2026-11-13 | 悬停热区：`resolvedRetentionPanelSize` + 展开地板；控制台 expand 先抬高；严格 ViewModel/中下点测试 |
| 2026-11-13 | 收起岛高改等于刘海高（`compactPanelHeight`），底边与刘海齐平；禁再 max(…, 38) 掉底 |
| 2026-11-13 | 展开动画默认改为「标准」档（`IslandAnimationSpeedPreset.standard` + `standardMotionDefault.v1`） |
| 2026-11-13 | 「全屏时禁用灵动岛」默认改回关（`hideFullscreenDefaultOff.v3`；曾短暂默认开） |
| 2026-11-13 | 「全屏时禁用灵动岛」默认改为开（`hideFullscreenDefaultOn.v2` 一次性迁移） |
| 2026-11-13 | 货架「磁吸拖放」设置开关：关则无接近区双舱 / 隔空传送，须拖入岛内感知区入舱 |
| 2026-11-13 | 媒体设置预览：收起定高贴真岛；展开顶用 `previewExpandedVisibleTopInset`（勿 0、勿照搬盲区顶距） |
| 2026-11-12 | 媒体展开翼行贴刘海：壳层顶距 0，禁负 padding（曾缩命中区致播放/切歌点不中） |
| 2026-11-12 | 详情预览恢复 tip360 / 媒体番茄380，仅库卡缩到 290；配置页不再套 library 缩放 |
| 2026-11-12 | 小组件库取消提示/实况/面板分段；扁平默认序：已复制第一、货架紧接专注计时后，音量倒数第二、项目最后；`WidgetLibraryLayout` + 迁移 v4 |
| 2026-11-12 | tip 预览恢复 hugs（禁强制 360）；番茄固定宽时高度仍 hugs，`minStageHeight` 只抬灰舞台；catalog `settings-preview-tip-forced-stretch` + stretch +1 |
| 2026-11-12 | 「已复制」改刘海右侧 Ø32 圆岛（方案 02 流光向心）；`usesNotchRightOrbChrome` + 预备布局 |
| 2026-11-12 | 电量预览暗淡：根因是样张 `Button.disabled` 降透明度 → 改 `allowsHitTesting`；catalog recurring |
| 2026-11-12 | 电量预览：锁深色 + sRGB 卡片色；去掉样张分页角点；顶距用可见 inset；catalog `settings-preview-island-appearance` |
| 2026-11-11 | 电量岛宽高随台数自适应（最多 3×2，超出纵滑）；两台不再留右侧黑空 |
| 2026-11-11 | 媒体：播放小岛常驻、点按展开大面板；预览去掉「收起待命」；catalog `media-compact-not-resident` |
| 2026-11-11 | 外设低电/满电/接入合并为 `builtin.peripheralTip`；「已复制」独立 `builtin.copiedNotice`；删除 liveInvite 残留 |
| 2026-11-08 | 初版：收录悬停热区、边距叠层、预览真数据为重复出现；录入复制提示缺失等 |
| 2026-11-08 | 录入 AI 额度账号作用域提示问题，并修换号嗅探 / 换回再弹 |
| 2026-11-09 | 录入取色后岛永久穿透假死；修 tip expand 抢前台 + Esc/超时退出 |
| 2026-11-10 | 录入 Continuity iPhone 不上列表；发现即上屏 + 重试冷却解耦 |
| 2026-11-10 | 录入提示/实况/面板上岛闸门与无面板禁悬停展开 |
| 2026-11-10 | 录入设置窗关不掉；presented 标记 + 关窗先 orderOut + 禁抬层 |
| 2026-11-10 | hover-retention +1（列表纵滑误收）；`scrollHold` + `RegressionCatalogTests`；recurring 改完必跑测 |
| 2026-11-10 | 录入 controldeck-init-battery-reentrancy；ControlDeck init 延后 start 会话 |
| 2026-11-10 | chrome-double-padding +1（会议 tip）；`IslandChrome.insets` + 强化自动化 |
| 2026-11-10 | 录入 tip-outline-capsule；瞬时提示（含会议）一律全胶囊，禁翼 tip 特判 panel |
| 2026-11-10 | 录入 island-focus-steal；悬停/展开不 activate，穿透即 resignKey |
| 2026-11-10 | tip-outline 改回 panel 上直角（occurrences=2，recurring） |
| 2026-11-10 | island-focus-steal +1：普通点击恢复 makeKey；入会改会话自开链接 |
| 2026-11-10 | 录入 meeting-tip-advance-next；多场会议 tip 可接力 |
| 2026-11-10 | 录入 meeting-tip-preemption；会议 tip 不被其它瞬时条盖住 |
| 2026-11-10 | 录入 live-invite-removed；电量/媒体去掉「打开」邀请 tip |
| 2026-11-10 | AI 额度 tip 改会议同款翼布局；重置文案三档（d/h/m） |
| 2026-11-10 | 取色 / 框选引导改久坐同款翼 tip；`usesNotchWingChrome`；「已复制」仍 shortTip |
| 2026-11-10 | shelf-copied-notice-miss +1：翼→短放行缩宽 + `test_shelfCopiedNoticeMiss_*` |
