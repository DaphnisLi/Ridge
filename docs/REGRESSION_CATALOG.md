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
| `island-hover-retention` | 岛悬停热区退化 | ≥10 | 展开后热区缩成刘海/短 tip；下移/拖一半就收；**选时更宽时 lastStable 更窄 → 右侧「正计时」出热区**；收起右翼贴边 morph 误收 | 保展开 `max(stable,panel)`；收起可点外扩；双翼地板；中下点/选时宽用例 |
| `media-compact-not-resident` | 播放大面板不得常驻 / 右计时翼 morph 误收 | ≥9 | 有曲目即大面板；双翼右翼误开媒体；**未出岛 morph 已收**；**点时长无效**；**离岛 morph 不恢复数字** | 右翼禁开媒体；Controller 钉 morph；离岛清 hover；整翼热区；`test_mediaCompactNotResident_*` |
| `island-chrome-double-padding` | 岛边距叠两层 | ≥6 | 内容根再加 padding / tip 误用大底距；**外设翼 tip 叠 bare / 右翼欠宽居中**；**新 tip 翼宽 ≠ preparedWingWidth** | `IslandChrome.insets`；`test_islandChromeDoublePadding_*`（含 wingTipCardsMatchPrepared） |
| `settings-preview-live-data` | 设置预览用真数据 | ≥2 | 库卡/详情拉实时源；空数据/网络抖时预览难看 | `test_settingsPreviewLiveData_*`：媒体/会议/电量假样张非空 + 股票固定两卡 |
| `shelf-copied-notice-miss` | 复制成功提示看不见 / 闪一下就没 / 触控板连震 / 音乐时整岛黑 | ≥10 | 取色/框选后看不见；关货架不上岛；hoverEnd 秒收；设置页连震；**播放中复制 DualNotchWingRow+GeoReader 空黑**；**库 sticky 误跳过投递** | 显式双翼宽高；`Surface.dualFlush` 零 inset；sticky 仍投递 copy；同指纹去抖；`test_shelfCopiedNoticeMiss_*` / dualSlots |
| `tip-outline-panel` | tip 上角圆/直角反复改 | ≥2 | 会议等 tip 上角与贴顶直角期望不一致 | 真岛/预览一律 `.panel`；`test_islandOutline_panelKeepsSquareTopCorners` |
| `island-focus-steal` | 岛抢焦点 / 矫枉按钮失灵 | ≥9 | 粘键盘；SwiftUI 首击无响应；**选时「正计时」只图标可点 / 写死宽右侧空白 / 播放抢页** | 自适应布局单测 + DirectHit + 挡媒体；`test_islandFocusSteal_picking*` |
| `library-island-stage-stretch` | 库卡/详情预览黑岛被拉高留空 | 5 | 黑岛过高；电量空黑；番茄垫高；**四 tip 库卡高低不齐** | 环 22；`meetingMatchedCompactChrome`；`test_libraryIslandStageStretch_*` |
| `island-bottom-corner-preview-dead` | 下圆角曲率调了没反应 | 2 | 迷你预览钳死；**库卡/详情写死半径不跟设置** | 壳 `nil`→设置；`test_islandBottomCornerPreviewDead_*` |
| `settings-preview-island-appearance` | 设置预览比真岛暗淡 | 2 | 文字/外设卡发闷；曾误画分页角点 | 禁预览 `.disabled`；深色+sRGB；`test_settingsPreviewIslandAppearance_*` |
| `shelf-magnetic-staging-double` | 磁吸双舱用完又冒一次 | ≥2 | 投放后双舱再闪；**未入舱松手后岛回头再开** | `fileDragCanceled` 强收 + 悬停冷却；双舱须 `fileDrag`；`test_shelfFileDragCancel_*` |
| `meeting-tip-stays-after-join` | 点入会后 tip 仍不消失 | ≥3 | 已入会仍贴着会前提示；tick/改选把同一场贴回 | 会话级 `dismissedAfterJoinID` + publish 拒投；`test_meetingTipAfterJoin_*` |
| `meeting-join-wrong-calendar-url` | 入会打开日程页而非会议室 | ≥2 | 点入会进 Google/Outlook 日程；钉钉丢会议号 | 跳过日程页；先扫平台；钉钉原 https；`test_meetingJoinLink_*` |
| `settings-session-swallows-transient-notice` | 设置开着 / 不悬停就看不见 tip | 3 | 改 RAM 阈值仅入槽；测试台创建会议悬停才见 | 仅设计 sticky 挡；`settingsBlocksProgrammaticNoticeExpand`；`test_shelfCopiedNoticeMiss_settingsBlocksStickyForceExpand` |
| `island-notice-layout-matrix` | 岛展示权重 / 左右组合漏测 | 2 | 音乐×专注、C 盖右翼专注、会议盖播放等组合易漏改 | 真值表 32 格 + 全 C 盖专注 + 翼宽 + 权重阶梯；`test_islandNoticeLayoutMatrix_*` |
| `island-notice-behavior` | 免打扰 / 自动收 / 收岛策略漏测 | 2 | 点免打扰 tip 仍挂；改阈值 mute 不失效；悬停空岛 | `shouldDismissNow` 时钟注入 + Center FIFO + 专注待命；`test_islandNoticeBehavior_*` |
| `ui-style-drift` | 修行为时顺手改样式 | ≥3 | 间距/字号/圆角/写死宽被「微调」；律动-时长距、胶囊宽、圆钮视觉径反复漂 | 令牌进 `*Metrics`/`UIStyleLock`；`test_uiStyleLock_*` 钉死数值 |

---

## 已记录问题（全量）

### island-hover-retention — 岛悬停热区退化

- **recurring:** true  
- **occurrences:** 10+（历史反复；2026-11-09 tip 污染 lastStable；2026-11-10 纵滑误收；2026-11-11 收起播放小岛两翼；2026-11-13 展开后下移一半仍收；**2026-11-13 非拖文件也认过大接近区**；**2026-11-24 计时右翼未出岛 morph/待命就收**；**同日选时岛 447 宽但 lastStable 334 → 右侧「正计时」出保展开、点字无效**）  
- **症状:** 大岛仍在，保展开/可点区退成刘海或 tip 小框；下移一半就收岛；短通知像「小岛盖住大岛」；控制台列表滚一半误收；**普通移入在刘海外很远就被「识别」展开**；**收起双翼/计时待命往右移未出岛，操作钮已收**；**选时右侧「正计时」只能点图标、往右移岛就收**  
- **根因倾向:** Preference 误报矮框；热区只用 `notchFrame`；瞬时短条写入 `lastStable`；纵滑无左键；收起 interactive 过紧；**`resolvedRetentionPanelSize` 只返回更高更窄的 stable，未并入当前更宽面板**  
- **防护:** 收起悬停展开 **仅刘海**；`fileDragApproachFrame` **仅**拖文件；展开态 `max(stable, panel)` 保展开 + `expandedRetentionFloor`；`scrollHold`；收起 interactive 外扩 + dualFlush/待命地板；选时「正计时」整颗胶囊 `contentShape`  
- **自动化:** `test_islandHoverRetention_*`（含 `pickingWiderThanStableUnionsWidth`）+ `test_islandHoverExpand_*`  
- **曾缺口（已补 2026-11-13 / 2026-11-24）:** Preference 未到 / 误报矮框；非拖文件误用大接近区；收起右翼贴边穿透；**选时宽于 lastStable**。  
- **日志锚点:** `指针离开保展开区，安排收起`；`收起待命可点区过窄，抬回可见宽`；`货架拖入：钉住展开`（须 `fileDrag=true`）；`保展开改用稳定面板尺寸`；`选时：点正计时起钟`

### island-chrome-double-padding — 岛边距叠两层

- **recurring:** true  
- **occurrences:** 6+（通知卡 / 多 widget 反复翻车；2026-11-10 会前提示 tip 根上再叠 nudge；**2026-11-23 外设满岛 tip 卡内再叠 bareContentLeading**；**同日右翼 fixedSize 欠宽，HStack+.frame 居中，左右外缘空一大截**；**同日网络 tip 翼宽硬编码 104 ≠ 壳层预备 98**）  
- **症状:** 下边距过大，左右离岛边过宽，或 tip 误用展开页大底距  
- **根因倾向:** 根视图 `.padding(.vertical/.horizontal)` / HTML `px/py` / 翼 tip `nudgeInward` / **满岛翼卡再叠 `bareContentLeading`** 叠 `IslandChrome`；**右翼不占满 `wingWidth` 导致整条居中**；**内容翼宽与 `preparedWingWidth` 不一致**；或未标 `usesNotchWingChrome` 退回 `contentBottom`  
- **防护:** 左右/底只走 `IslandChrome.insets(for:)`；widget/通知卡根视图只排内容；满岛 tip `liveWingWidth == preparedWingWidth`（或外设 `preparedPeripheralWingWidth`）；左右翼各 `frame(width: wingWidth)`；`bareContentLeading` 仅 dualFlush bare  
- **自动化:** `RegressionCatalogTests.test_islandChromeDoublePadding_*`（令牌 + surface inset + `peripheralWingTipOuterInsetIsChromeOnly` + `wingTipCardsMatchPreparedWingWidth`）

### settings-preview-live-data — 设置预览用真数据

- **recurring:** true  
- **occurrences:** 2（股票库卡多卡真价感；此前其它 widget 同类）  
- **症状:** 无数据/网络失败时预览空或「更新中」；库卡裁切多卡  
- **根因倾向:** 预览直连 Session / 实时源；样张塞满多枚  
- **防护:** `WidgetSamplePreview.island` / `SettingsIslandPreviewCard`；假数据固定形态（股票两卡样张）  
- **自动化:** `test_settingsPreviewLiveData_stockSampleUsesFixedFakePair`、`test_settingsPreviewLiveData_widgetSamplePreviewUsesFakeSamples`（媒体/会议标题非空、电量 hugs + opaque）

### library-island-stage-stretch — 库卡/详情预览黑岛被拉高留空

- **recurring:** true  
- **occurrences:** 5（2026-11-09 股票；2026-11-11 电量；2026-11-12 minStageHeight；同日专注环垫高；**2026-11-24 外设/本机电池/网络/专注 tip 库卡窄内容同比放大后黑岛虚高不一致**）  
- **症状:** 库卡/详情预览黑岛呈过高矩形；股票卡被撑高；电量样张卡片贴顶、下半截空黑；番茄待命黑岛比内容高一截；四 tip 库卡灰舞台内黑岛高低不齐  
- **根因倾向:** 对岛施 `maxHeight: .infinity` / 写死双行高；样张行数与占位高度不一致；**`hugsContent: false` 时把 `minStageHeight` 写在岛 frame 上**；进度环大于媒体封面、预览垫高不一致；**tip 未走 `meetingMatchedCompactChrome`，固有宽 <290 时库卡 scale>1 把高度放大**  
- **防护:** 库卡岛 `.fixedSize(vertical: true)`；窄 widget `hugsContent`；`batterySample` 按单行样张高度；固定预览宽时高度仍 hugs；**`FocusTimerCompactMetrics` 环 22、预览上下 6 / minHeight 36 对齐媒体**；**外设/本机电池/网络/专注库卡与会议同款 `meetingMatchedCompactChrome`（290×30），compact 翼宽 90×2+110**  
- **相关代码:** `FocusTimerCompactMetrics`、`WidgetSamplePreview.*TipSample`、`SettingsIslandStage.stageCanvas`、`meetingMatchedCompactChrome`  
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
- **症状:** 拖文件出磁吸暂存面后入舱完成再闪一次；或拖近展开后**未放暂存区就松手**，岛收起后又自动打开（历史含右舱隔空完成再闪；隔空舱已移除）  
- **根因倾向:** ① `isTargeted` 滞后再 `setActive(true)`；② 拖文件 `shelfDropApproach` 展开后松手仍 `retention=true`（大面板）不收；③ 松手后普通悬停立刻再 expand  
- **防护:** `endAfterDrop` 冷却；磁吸暂存须 `fileDrag`；**未入舱松手 `fileDragCanceled` 强收 + `postFileDragHoverSuppress`**；收起悬停仅刘海，接近区仅拖文件  
- **自动化:** `test_shelfMagneticStagingDouble_*`、`test_shelfFileDragCancel_*`、`test_islandHoverExpand_*`

### shelf-copied-notice-miss — 复制成功有时不上岛提示

- **recurring:** true  
- **occurrences:** 10（…；设置页连震；dual 会议翼宽黑条；**2026-11-16 DualNotchWingRow+GeometryReader 在 fixedSize 下理想宽≈0 → 只剩黑底**；**2026-11-27：引导结束打开小组件库 sticky 时剪贴板层误 `blocksProgrammaticNoticeExpand` 直接跳过投递**）  
- **症状:** 复制文字/链接/颜色/截图后不出现「已复制」；取色/框选后尤甚；tip 开着但货架关时 Cmd+C 也不上岛；**或刚展开就收起、几乎看不清**；**或一点复制触控板一直震**；**或正在播放时复制灵动岛全黑**；**或设置小组件库开着复制无圆岛**  
- **根因倾向:** ① dismiss 后再 present 会先收岛；② 翼→短/圆岛 Preference 缩宽被误缩守卫拒绝；③ `showCopiedNotice` 关；④ 剪贴板轮询只跟货架模块走；⑤ **`copy.*` 未 `keepsExpandedWithoutHover`，指针不在岛上时 0.1s 后 hoverEnd 收岛**；⑥ **设置设计页 sticky↔pointerOverSettings 互殴连震**；⑦ **同指纹短时内 changeCount 抖动反复 present + haptic**；⑧ **expand(notice) 误走控制台画布盖掉 Ø32**；⑨ **media+copy dual 误用会议双翼宽**；⑩ **`IslandDualNotchWingRow` 用 GeometryReader + IslandBody `.fixedSize` → 内容塌宽，OpaqueFill 仍铺满 → 全黑**；⑪ **剪贴板层用设计 sticky 提前 return，与 `expandsDuringSettingsSession` 矛盾**  
- **防护:** `ClipboardCopiedNoticeGate.syncClipboardMonitoring`；**`prepareNotchRightOrbLayout`（Ø32 圆岛）**；翼→圆岛放行；**`copy.*` 保持展开至入场+定格（`notchRightOrbAutoDismissNanoseconds` ≈1.4s）再收，不悬停续命**；clamp 不得把 Ø32 抬到刘海宽；**`copy.*` 有自动收起 → 设置 sticky 也投递并程序展开（勿在 `ClipboardHistoryStore` 用 `blocksProgrammaticNoticeExpand` 跳过）**；**同指纹 2s 去抖**；**notice expand 套 `applyNoticeTipPanelSizeIfNeeded`**；展开触感 0.4s 节流；**`usesDualFlushChrome`：左右各自 flush OpaqueFill + underlap；右圆岛时仅左填、Ø32 自绘**；**双槽 tip 一律 `bareWingContent`（对齐音乐三区，禁再套黑胶囊）**；**双槽禁 GeometryReader**；**`Surface.dualFlush` 零 inset**  

- **相关代码:** `ClipboardCopiedNoticeGate`、`IslandNoticePayload.usesNotchRightOrbChrome`、`IslandExpandedPanelPolicy`、`ClipboardCopiedIslandView`、`IslandDualNotchWingRow`、`IslandController.blocksProgrammaticNoticeExpand`、`IslandNoticeSlots.usesDualFlushChrome`、`IslandChrome.Surface.dualFlush`  
- **自动化:** `RegressionCatalogTests.test_shelfCopiedNoticeMiss_*`、`test_islandNoticeDualSlots_*`（含 media+copy dualFlush 零 inset）、`IslandExpandedPanelPolicyTests`

### meeting-join-wrong-calendar-url — 入会打开日程页而非会议室

- **recurring:** true  
- **occurrences:** 2+（2026-11-16：Google 日程页盖住 Zoom；要求进 recurring 套件）  
- **症状:** 点「入会」打开 Google/Outlook 日程详情，或钉钉进无会议号的空页  
- **根因倾向:** EventKit `url` 常是日历事件页；`detect` 先吃任意 https 当 generic，盖住 notes 里的 Zoom/腾讯等；钉钉深链写成通用 conference 丢号  
- **防护:** 识别并跳过日历事件页；先扫已知平台；泛型 https 仅从 location/notes；钉钉用原 https；会话 `joinOpenURL` 用 detector 结果  
- **自动化:** `test_meetingJoinLink_*`（日程页跳过 / location·notes 优先 / 泛型仅文本 / Session 打开深链而非日历页）

### meeting-tip-stays-after-join — 点入会后 tip 仍不消失

- **recurring:** true  
- **occurrences:** 3+（2026-11-16 多次：仅靠 widget weak `onJoined` 打标会丢；tick 再 present）  
- **症状:** 已点「入会」并拉起客户端，灵动岛会前提示仍在  
- **根因倾向:** `dismissedAfterJoinID` 只活在 widget；`onJoined` weak self 未命中；1s tick / `joinedAdvance` 在打标前把同一场再 present；`open` 失败曾直接 return 不撤 tip  
- **防护:** `MeetingLeadSession` 会话级先打 `dismissedAfterJoinID` → `publish(nil)` → `onTipExpired(joinedAdvance)`；`publish` 拒投已入会 id；打开失败也撤 tip；widget 只读会话标  
- **自动化:** `test_meetingTipAfterJoin_*`（含 Session `joinFromNotice` 撤 tip + 拒再 present + selector latch）

### settings-session-swallows-transient-notice — 开着设置改阈值时 tip 入槽但看不见

- **recurring:** true  
- **occurrences:** 3（2026-11-17：仅入槽不展开；同日悬停才见；2026-11-22：岛测试台创建会议同样「入槽不展开、悬停才见」）  
- **症状:** 设置「RAM 监控」开着时改阈值 / 告警已触发，岛上没有任何 tip；或必须把鼠标移入灵动岛才出现；测试台创建会议同款  
- **根因倾向:** 曾把任意「收起设置会话」当成 `blocksProgrammaticNoticeExpand`，挡住会议等无自动收 tip 的程序 expand；`expand(hover)` 不走该挡 → 「靠悬停才展示」  
- **防护:** `blocksProgrammaticNoticeExpand` **仅**小组件库 / 控制台设计 sticky（`designSticky`）；岛测试台 / 普通设置不挡；瞬时 tip 仍靠 `expandsDuringSettingsSession`；`pointerOverSettings` / `hoverEnd` 不收 `keepsExpandedWithoutHover`  
- **相关代码:** `IslandExpandedPanelPolicy.settingsBlocksProgrammaticNoticeExpand`、`IslandController.beginSettingsSessionCollapsed(designSticky:)`、`IslandNoticeWidget.showThenExpand`  
- **自动化:** `test_shelfCopiedNoticeMiss_settingsBlocksStickyForceExpand`（含 designSticky 门闩 + 瞬时 tip force expand）  

### island-notice-layout-matrix — 岛展示权重 / 左右组合漏测

- **recurring:** true  
- **occurrences:** 2（2026-11-17：音乐×专注并存规则；同日固化取色/会议>播放>专注>C 与 C 盖右翼专注）  
- **症状:** 改布局只测几条组合，其它格（会议+播放+专注+C 等）易漏改、行为漂移  
- **根因倾向:** 布局是多维真值表，零散 assert 盖不全；新增 tip case 不进契约表  
- **防护:** `IslandNoticeLayoutMatrixTests`：A×会议×播放×专注×C 共 32 格；全部 tip 契约穷尽 switch；投递/FIFO/独占；C 盖专注再恢复；**权重阶梯命名规则**；**每一种 C** 盖右翼再恢复；有 B 时 C 永不占左；RAM/进程结束单独紧凑翼 vs 并排标准翼  
- **相关代码:** `IslandNoticeSlotPolicy.resolvedLayout`、`IslandNoticePayload`  
- **自动化:** `test_islandNoticeLayoutMatrix_*`（进 recurring 套件）

### island-notice-behavior — 免打扰 / 自动收 / 收岛策略漏测

- **recurring:** true  
- **occurrences:** 2（2026-11-17：免打扰 tip 不立刻消失；改阈值须清 mute）  
- **症状:** 点免打扰后 tip 仍挂；改阈值后仍被旧 mute 挡住；悬停留下空双翼  
- **根因倾向:** 行为散落在 Session/Widget，无纯策略可测；共享单例易漏断言  
- **防护:** `IslandNoticeAutoDismissPolicy` / `IslandNoticeEndCollapsePolicy`；`muteAlerts30m` 撤 RAM；`rearm` 清 mute；**`shouldDismissNow` 可注入时钟**（不必真 sleep 3s）；Center FIFO + 独占清队；专注待命仅计时/加时  
- **相关代码:** `IslandNoticeDismissPolicy`、`ResourceMonitorSession.muteAlerts30m` / `rearmAlertAndEvaluate`  
- **自动化:** `test_islandNoticeBehavior_*`  

### ui-style-drift — 修行为时顺手改样式

- **recurring:** true  
- **occurrences:** 3+（2026-11-24：律动↔时长间距反复拧；选时绿胶囊写死宽留白；待命圆钮/字号在修命中时被顺手改）  
- **症状:** 用户确认过的岛上长相被 Agent「修点不了 / 悬停」时一起改掉；间距、字号、圆角、固定宽高漂移  
- **根因倾向:** 行为修复与可见样式未分离；魔法数散落 View 内，无单测钉死  
- **防护:** 易漂令牌进 `MediaCompactStandbyMetrics` / `IslandFlushWingStyle` / `FocusTimerCountUpButtonLayout` / `IslandStandbyControlChrome` / `IslandChrome`；登记 `UIStyleLock.pinnedModuleIDs`；规则 `ui-style-lock.mdc`  
- **相关代码:** `UIStyleLock.swift`、各 `*Metrics` / 翼样式枚举  
- **自动化:** `test_uiStyleLock_*`（含 `everyPinnedModuleHasAnchoredTest`）；改数值必须同步期望值，否则 recurring 套件红  

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
- **occurrences:** 9（抢焦点；矫枉后按钮失灵；翼 tip 可点区过窄点穿；2026-11-12 媒体；2026-11-13 混音台；2026-11-16 久坐 +10m；2026-11-24 正计时暂停/结束点空；同日选时「正计时」只图标可点；**同日播放时三字仍无反应 + 写死宽右侧空白，补布局/挡媒体/Hosting 优先级单测**）  
- **症状:** 悬停或点过岛后其它 App 点不进；或会议「进入」/媒体/混音台/久坐「+10m」/计时待命钮/选时「正计时」点了没反应；选时绿胶囊右侧虚空  
- **根因倾向:** 一律 `activate`；`hosting` 吞掉 SwiftUI 首击；可编辑字段外溢抢点；播放 `compactHover` 抢选时页；**选时绿胶囊写死宽 / 热区缩成图标**  
- **防护:** 普通点击只 `makeKey`；选时正计时 `FocusTimerCountUpButtonLayout` 自适应宽 + HitView/`IslandDirectHitTarget`；Hosting 控件优先于可编辑；`MediaFocusPickingGate` 挡媒体抢页  
- **相关代码:** `FocusTimerCountUpButtonLayout`、`MediaFocusPickingGate`、`IslandHostingHitPolicy`、`FocusTimerCountUpHitView`  
- **自动化:** `test_islandFocusSteal_pickingCountUpButtonFitsTitleHitArea`、`test_islandFocusSteal_pickingBlocksMediaCompactExpand`、`test_islandFocusSteal_hostingPrefersDirectControlOverEditable` + 既有 `test_islandFocusSteal_*` / `test_islandFocusPolicy_*`

### tip-outline-panel — 瞬时提示上直角下圆角

- **recurring:** true  
- **occurrences:** 2（2026-11-10：先改四角等弧，后改回上直角）  
- **症状:** tip 上角圆/直角与产品期望反复不一致  
- **根因倾向:** tip 外形在 `.capsule` / `.panel` 间摇摆  
- **防护:** 真岛与设置预览一律 `IslandOutlineStyle.panel`（左上/右上直角、下圆角）  
- **相关代码:** `IslandContentView.outlineStyle`、`WidgetSamplePreview.outlineStyle(for:)`、各 tip 配置页  
- **自动化:** `RegressionCatalogTests.test_islandOutline_panelKeepsSquareTopCorners`

### island-bottom-corner-preview-dead — 下圆角曲率调了没反应

- **recurring:** true  
- **occurrences:** 2（2026-11-23：几何迷你预览矮条钳死；**2026-11-24：库卡/详情 tip 预览写死 16/18/26，不跟设置左下/右下**）  
- **症状:** 调下圆角曲率像没生效；库卡/小组件详情预览下圆角与「灵动岛」设置不一致  
- **根因倾向:** 迷你预览高仅 24pt，半高钳制把 ≥12 的半径压成同形；开设置时真岛收起，收起态半高亦钳大半径；**`WidgetIslandPreviewShell` compact 写死 16、各 tip `bottomRadius: 18`**  
- **防护:** `IslandBottomRadiusPolicy.settingsGeometryPreviewHeight ≥ 2×32`；预览用 `clamped`；真岛走 `applied`；预设档 8/18/24（默认 18），滑条仍到 32；**库卡/详情壳 `bottomRadius == nil` → `IslandSettings.bottomCornerRadius`**  
- **相关代码:** `IslandBottomRadiusPolicy`、`IslandSettingsPane.geometryMiniPreview`、`IslandContentView.appliedBottomRadius`、`WidgetIslandPreviewShell`、`SettingsIslandStageOption`  
- **自动化:** `RegressionCatalogTests.test_islandBottomCornerPreviewDead_*`

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

- **recurring:** true  
- **occurrences:** 9（2026-11-11：有曲目即常驻大面板；2026-11-23：左音乐右专注时悬停右翼不展开；同日产品改右翼 morph 专注钮；同日：右翼操作钮未及左右缘就收；2026-11-24 计时往右移未出岛 morph 已收；同日正计时每秒 allowPanelShrink 抖 hover/点空；同日 OpaqueFill 抢击 + trailing 分界过严；同日往右移未出岛 morph 已收，且只有图标可点、点时长无反应；**同日：离岛后 morph 不恢复数字；播放+正计时点时长无反应、往右滑未出岛就收**）  
- **症状:** 有曲目即 admit/自动 expand；或双翼时移入右计时翼误开媒体；或悬停出 `+Nm`/暂停后移向边缘即收回；正计时钮点了没反应；播放中右翼按钮点空；**点时长文字无效**；**指针离开后操作钮不收回、数字不恢复**  
- **根因倾向:** 有曲目即 admit；右翼整块曾进 `compactHover`；收起 interactive 过紧；正计时每秒缩扩；OpaqueFill 抢击；trailing 分界过严；仅 SwiftUI onHover 钉 morph；**onHover 离开时因 trailingPinned 跳过清 `isWingHovering`，离岛后 morph 粘住**；media 旗标用 `isVisiblyShowingCompact` 与双翼 UI 不同步  
- **防护:** 右计时翼禁开媒体；`collapsedInteractivePadX≥28`；OpaqueFill 不抢击；trailing 含 underlap；**`FocusTrailingWingHover` 钉住+解除去抖**；本地 hover 离开必清 `isWingHovering`；闲态整翼 Button；时长区可点；media 用 `isActive`  
- **相关代码:** `FocusTrailingWingHover`、`FocusTimerStandbyView`、`IslandOpaqueFillView`、`IslandExpandedPanelPolicy`  
- **自动化:** `test_mediaCompactNotResident_*`；`test_islandHoverRetention_collapsedInteractivePadsFocusTrailingWing`

### media-click-opens-empty — 播放中点刘海落到空态

- **recurring:** false  
- **occurrences:** 1（2026-11-14：播放中点刘海左翼出现「尚未添加小组件」）  
- **症状:** 正在播放小岛可见时，点击/按住刘海或两翼展开成空态页，而不是媒体控制面板  
- **根因倾向:** 收起态可点两翼；左键按下走 `dragHold` 裸 `expand`，早于 `MediaCompactPresence.openExpandedPanel`；无面板争夺时 `activeID=system.empty`  
- **防护:** `dragHold`/`scrollHold`/`hover` 先尝试开媒体；`shouldExpandForPointerInteraction` 禁止纯空态指针展开；关键路径 warn  
- **相关代码:** `IslandController`、`MediaCompactPresence.openExpandedPanel`  
- **自动化:** 不强制（occurrences=1）

### ocr-empty-notice-noise — OCR 无文字不应上岛报错

- **recurring:** false  
- **occurrences:** 1（2026-11-14：框选无字冒「选区内未识别到文字」打扰）  
- **症状:** OCR 空结果投递 `ocr.empty` 瞬时条，误点/空选区也会占岛  
- **根因倾向:** `finishOCR` 空串分支 `present(.clipboardCaptureHint)`  
- **防护:** 无文字时静默 dismiss tip + 非悬停则 collapse；仅日志 `OCR 无文字，已静默收起`  
- **相关代码:** `ShelfCaptureTools.finishOCR`  
- **自动化:** 不强制（occurrences=1）

### screen-capture-double-prompt — 屏幕录制小窗与设置页叠开 / 列表无 App

- **recurring:** false  
- **occurrences:** 2（2026-11-16：① 小窗未点设置页已开；② 只开设置页则列表无 Ridge）  
- **症状:** request+open 双开；或只 open 时「录屏与系统录音」列表里没有本 App  
- **根因倾向:** 须 `CGRequestScreenCaptureAccess` 才登记进 TCC 列表；新系统上 request 几乎立刻返回，若紧接着 `SystemPrivacyOpener` 会与小窗叠开  
- **防护:** 本进程首次只 `CGRequest`（由小窗「打开系统设置」进页）；再次点击才 `open(Privacy_ScreenCapture)`；通用设置走同一 `ensureOne`  
- **相关代码:** `WidgetPermissionGate.ensureScreenCapture`、`GeneralSettingsPane`  
- **自动化:** 不强制（occurrences=1 档，尚未 recurring 闸）

### onboarding-perms-skip-ahead — 引导权限未齐就进自启页

- **recurring:** false  
- **occurrences:** 2（2026-11-16：第三项未同意已到开机自启；**2026-11-27：全部授权后仍显示「授权」、未进自启**）  
- **症状:** 权限步在队列空 / 蓝牙异步未决时跳到下一步；**或**用户已全部授权、重开后主按钮仍是「授权」不进下一步  
- **根因倾向:** 以 `permissionQueue.isEmpty` 为跳步条件；蓝牙 `start()` 后立即 `stillNeeded`；**重开瞬间 TCC 探针滞后 → `allSelectedPermissionsSatisfied` 假阴性又 rebuild 队列**  
- **防护:** 以 `allSelectedPermissionsSatisfied()` 为准；齐了主按钮改「继续」并自动进自启；`refreshSatisfactionProbes` + 短延迟重试；未齐才留页  
- **相关代码:** `OnboardingProgress`、`OnboardingController.syncPermissionsStep`、`WidgetPermissionGate.refreshSatisfactionProbes`  
- **自动化:** 不强制（occurrences=2，尚未 recurring 闸）

### onboarding-window-buried — 引导窗被其它 App 盖住

- **recurring:** false  
- **occurrences:** 1（2026-11-27：授权后重开 / 出窗后不在最前；同日修浮动层时 `canJoinAllSpaces`+`moveToActiveSpace` 断言崩；浮动层又盖住系统权限窗）  
- **症状:** 欢迎引导不在屏幕最前，被 Cursor / 系统设置等盖住，要找才看得到；或一出引导即 SIGABRT；或引导压住系统授权框  
- **根因倾向:** LSUIElement accessory 冷启动 activate 不稳；岛收起/穿透后 `demoteIslandInteractionIfNeeded` 降回 accessory；**`collectionBehavior` 不可同时含 `canJoinAllSpaces` 与 `moveToActiveSpace`**；**.floating 会盖住系统设置/TCC 框**  
- **防护:** 普通窗层级；授权前 / `willResignActive` `yieldFrontForSystemUI`；仅 `moveToActiveSpace`+`fullScreenAuxiliary`；`isPresenting` 时禁降 accessory；`didBecomeActive` 再前置  
- **相关代码:** `OnboardingController`、`IslandController.demoteIslandInteractionIfNeeded`、`AppDelegate`  
- **自动化:** 不强制（occurrences=1）

### focus-timer-standby-side-margins — 计时待命左右边距不对称

- **recurring:** false  
- **occurrences:** 1（2026-11-24：正计时满岛左环离边过远、右结束钮贴圆角）  
- **症状:** 左内边距明显大于右；结束圆钮贴下圆角弦  
- **根因倾向:** 对称 `horizontal=14`；环/勾有字形内白、圆钮实心外缘 + 下圆角裁切，视觉右更贴  
- **防护:** `focusTimerStandbyLeadingPadding=10`（对齐媒体）、`TrailingPadding=16`；终局右翼回车略收 trailing  
- **相关代码:** `NotchGeometry.focusTimerStandbyLeadingPadding`、`FocusTimerStandbyView.fullStandbyBody`  
- **自动化:** 不强制；`test_focusTimerStandbySideMargins_trailingClearsCorner`

### focus-completed-countup-duration-wrong — 正计时终局时长进位成 1h 12m

- **recurring:** false  
- **occurrences:** 1（2026-11-24：正计时约 1h11m 结束，左翼显示 `1h····12m`）  
- **症状:** 终局绿勾旁时长与进行中墙钟不一致；整分进位；等宽 `1h 12m` 字缝过大  
- **根因倾向:** 终局一律 `compactDuration((elapsed+59)/60)`；snapshot 终局丢失 kind；等宽字体撑开空格  
- **防护:** `completedDurationLabel`：正计时走 `countUpClock`；倒计时整分不进位；snapshot 带 `kind`；结算写回 `elapsedSeconds`  
- **相关代码:** `FocusTimerFormatting.completedDurationLabel`、`FocusTimerCompletedView`、`FocusTimerSession.finalizeRecord`  
- **自动化:** 不强制（occurrences=1）；`RegressionCatalogTests.test_focusCompletedCountUpDuration_matchesRunningClock`

### focus-completed-clipped-by-notch — 终局顶空过大 / 高度掉出刘海

- **recurring:** false  
- **occurrences:** 4（2026-11-23：① 顶距 6 被挡；② 行内右缘空；③ 仅把间隙 +6→+2 用户无感；**2026-11-24：④ 终局高=刘海+compactTipBottom，底边掉出刘海**）  
- **症状:** 终局上半截大块空黑；或底边明显低于刘海下沿  
- **根因倾向:** 终局曾走展开页大顶距；改翼 tip 后仍叠 `compactTipBottom`（预备高 = 刘海+4）  
- **防护:** `preparedFocusCompletedPanelSize` 高=刘海；壳层终局底距 0；`forcePanelSize` 写入该矮高  
- **相关代码:** `IslandChrome.preparedFocusCompletedPanelSize`、`FocusTimerCompletedView`、`IslandContentView.contentBottomInset`  
- **自动化:** `RegressionCatalogTests.test_focusCompletedClippedByNotch_topInsetClearsNotch`

### focus-completed-half-island-miss — 半岛待命结束未见全岛完成态

- **recurring:** false  
- **occurrences:** 1（2026-11-23：左音乐右专注半岛结束，完成态未占满全岛 / 秒收）  
- **症状:** 双翼待命点结束或倒计时归零后，看不到全岛终局（绿勾+时长+备注），或闪一下被 hoverEnd 收掉  
- **根因倾向:** 终局 `expand` 后指针不在保展开区 → `scheduleCollapse` → `dismissCompletion`；媒体闸未关可能抢页  
- **防护:** `keepsIslandExpandedWithoutHover`（`phase==completed`）；`hoverEnd` / 收起前复查与会议 tip 同挡；完成时 `close` 媒体闸；未展开则 sticky 强制全岛终局  
- **相关代码:** `FocusTimerSession.complete`、`keepsIslandExpandedWithoutHover`、`IslandController.keepsExpandedWithoutHoverNow`  
- **自动化:** `IslandNoticeBehaviorTests.test_islandNoticeBehavior_focusCompactStandbyOnlyWhileTiming`（含终局 keep）

### peripheral-wing-floor-meeting-width — 外设收窄后左右间距仍不对

- **recurring:** false（外缘叠距并入 `island-chrome-double-padding`）  
- **occurrences:** 3（2026-11-23：① 地板抬成会议翼；② 卡内再叠 bareContentLeading；③ 右翼 fixedSize 欠宽居中，左右空档过大）  
- **症状:** 外设满岛 tip 视觉上仍偏宽或右/左缘空一大截；设备名与电量% 离岛边不对齐  
- **根因倾向:** ① `wingTipInteractivePanelSize` 默认抬会议 98 翼；② 满岛卡再叠 `bareContentLeading`；③ 右翼未占满 `wingWidth`  
- **防护:** `wingTipPreparedWingWidth`；卡根零外缘 padding；左右翼各占满 `wingWidth`（右 trailing）；外缘只靠 `notchWingTip` chrome  
- **相关代码:** `IslandExpandedPanelPolicy.wingTipInteractivePanelSize`、`IslandNoticeSlots`、`IslandController`、`PeripheralBatteryNoticeCard`  
- **自动化:** `test_peripheralWingFloorMeetingWidth_*` + `test_islandChromeDoublePadding_peripheralWingTipOuterInsetIsChromeOnly`

### bluetooth-hid-input-monitoring — 开蓝牙外设电量却弹出输入监控

- **recurring:** false  
- **occurrences:** 1（2026-11-16：引导第三项「蓝牙与外设」授权时顺带弹出键盘/输入监控）  
- **症状:** 只申请蓝牙时，系统还弹出「输入监控」或隐私列表里多了击键相关项  
- **根因倾向:** `BatterySession.start` → `BatteryHIDProbe` 用 `IOHIDManagerSetDeviceMatching(nil)` 打开全部 HID（含键盘）；新系统把「打开键盘类 HID」当成输入监控场景；且蓝牙对话框未决时仍立刻扫 HID，两弹叠出  
- **防护:** HID 仅匹配 Battery System（0x85），禁止 nil matching；`CBManager.authorization == .notDetermined` 时跳过 HID；蓝牙申请路径打 warn 说明  
- **相关代码:** `BatteryHIDProbe`、`BatterySession.refresh`、`WidgetPermissionGate.ensureBluetooth`  
- **自动化:** 不强制（occurrences=1）

### sound-app-volume-host-key — 按 App 音量对不上宿主进程

- **recurring:** false  
- **occurrences:** 1（2026-11-13：汽水音乐 / iPhone 镜像滑条无实际音量变化）  
- **症状:** 混音台能列出正在播放的 App，拖滑条 / 静音听感不变  
- **根因倾向:** UI 行按宿主 bundle 聚合，`applyRoute` 却用进程自身 `bundleID == key` 过滤；Helper 空匹配后静默 return；滚动区 `compositingGroup` 亦可能吞 AppKit 滑条命中  
- **防护:** `SoundProcessMonitor.processObjectIDs(forHostKey:)` 与聚合同 key；混音台滚动关 compositing；关键路径 warn 落盘  
- **相关代码:** `SoundSession.applyRoute`、`SoundProcessMonitor.hostKey`、`AlwaysVisibleScrollView.usesCompositingGroup`  
- **自动化:** `RegressionCatalogTests.test_soundAppVolumeHostKey_helperBundleDoesNotEqualHostKey`

### keystroke-peak-hour-not-max — 击键峰值不是当天最多时段

- **recurring:** false  
- **occurrences:** 1（2026-11-14：专注洞察「峰值时段」与直觉不符 / 重启后丢）  
- **症状:** 峰值不是当日小时桶击键最多的整点；或重启后峰值空白/错位  
- **根因倾向:** ① 误用非「当日各小时计数取 max」的语义；② `todayHourlyKeystrokes` 未持久化，进程重启桶清空  
- **防护:** `ResourceActivityStore.peakHour(from:)` 取 count>0 的 max（并列较早小时）；桶随日聚合 `persist`/`load`；峰值变化打 `击键峰值时段已更新`  
- **相关代码:** `ResourceActivityStore.addKeystrokes` / `peakKeystrokeHourRange` / `persist`  
- **自动化（可选）:** `KeystrokePeakHourTests`（max / 首击即峰 / 后时段反超 / 并列取早 / 空或 0 为 nil）

### move-reminder-hard-to-trigger — 久坐提示长期看不到

- **recurring:** false  
- **occurrences:** 1（2026-11-14：用户反馈从未见久坐 tip；当日日志无 MoveReminder 行）  
- **症状:** 久坐起身从不 / 极少上岛；落盘日志也查不到累计过程  
- **根因倾向:** ① 须连续在场满 `activeTrigger`（默认 30m），且 HID 空闲一超过 `leaveReset`（默认 5m）就清零——读文档停手也会重置；② App 重启累计归零（开发日频繁 relaunch 尤其明显）；③ 会话关键路径用 `info`，而 `AppLog` 仅 warn/error 落盘，排障看不见  
- **防护:** 启动 / 离开清零 / 每 5 分钟进度 / 触阈投递 / 关闭组件 一律 `warn` 落盘；设置文案已说明「键鼠持续交互」  
- **相关代码:** `MoveReminderSession.tick` / `MoveReminderIdleProbe`  
- **自动化建议:** 可选：模拟 idle≥leave 须清零、accum≥trigger 须 present

### ram-mute-tip-stays — 点免打扰后 RAM tip 不立刻消失

- **recurring:** false  
- **occurrences:** 1（2026-11-17：悬停点免打扰后 tip / 空双翼仍挂着）  
- **症状:** 点免打扰后提示不马上收；仍悬停时可能留下空翼岛  
- **根因倾向:** ① 浮层上 SwiftUI `Button` 易点不中；② `hide()` 用 `allowsHoverExpand` 保展开时，瞬时通知页 / `current` 未清也会被当成可保展开  
- **防护:** 免打扰走 `onTapGesture`；`muteAlerts30m` 同步撤 RAM tip；`hide()` 仅在通知真正撤干净且仍有面板/实况时保展开；点击后再 `collapse(ramMute)`  
- **相关代码:** `RAMPressureNoticeCard`、`ResourceMonitorSession.muteAlerts30m`、`IslandNoticeWidget.hide`  
- **自动化建议:** 可选：mute 后 slots 无 ramPressure，且 hide 在 transient 残留时仍 collapse

### process-ended-tip-stale-dismiss — 进程结束 tip 不自动消失

### mac-battery-tip-miss-on-ac — 本机插电看不到 tip

- **recurring:** false  
- **occurrences:** 1（2026-11-22：优化充电 AC attached / not charging；仅认 `isCharging` 边沿；会话未在启动拉起）  
- **症状:** 已开「本机电池」、笔记本已接电，岛上无充电 tip；日志无 `MacBattery` 投递  
- **根因倾向:** 把「正在充电」当「插入电源」；优化充电暂停时 `isCharging=false`；未订阅 IOPS 电源变化、启动未 `start` 会话  
- **防护:** 以 AC 接电边沿触发充电 tip；`IOPSNotification` + AppDelegate 启用时启动会话；设置页可试投样张  
- **自动化:** 不强制（occurrences=1）


- **recurring:** false  
- **occurrences:** 1（2026-11-22：测试台进程结束 tip 挂住；正式路径在 `lastWatchEnded` 旧 id 时同病）  
- **症状:** 约 3s 后应自动收的进程结束 tip（含测试台）一直不消  
- **根因倾向:** `finishDismiss` 对 `.processEnded` 只调 `dismissWatchEnded()`，按控制台 `lastWatchEnded.id` 撤槽；测试台 tip 另有 id、或控制台仍留着旧 ended → 撤错条，岛上 tip 残留  
- **防护:** 自动收起一律 `IslandNoticeCenter.dismiss(id: tipID)`；再 `clearWatchEndedIfMatching` 仅同源清控制台；`ProjectWatchEndedDismissSync`  
- **相关代码:** `IslandNoticeWidget.finishDismiss`、`ProjectReleaseSession.clearWatchEndedIfMatching`  
- **自动化建议:** `test_islandNoticeBehavior_processEndedDismissByTipIDNotStaleLocal`（occurrences=1，不强制每次跑）

### mac-battery-tip-miss-on-ac — 本机插电看不到 tip

- **recurring:** false  
- **occurrences:** 1（2026-11-22：优化充电 AC attached / not charging；仅认 `isCharging` 边沿；会话未在启动拉起）  
- **症状:** 已开「本机电池」、笔记本已接电，岛上无充电 tip；日志无 `MacBattery` 投递  
- **根因倾向:** 把「正在充电」当「插入电源」；优化充电暂停时 `isCharging=false`；未订阅 IOPS 电源变化、启动未 `start` 会话  
- **防护:** 以 AC 接电边沿触发充电 tip；`IOPSNotification` + AppDelegate 启用时启动会话；设置页可试投样张  
- **自动化:** 不强制（occurrences=1）

### airdrop-receive-miss — 隔空收视频/文件岛上无提示

- **recurring:** false  
- **occurrences:** 1（2026-11-27）  
- **症状:** 手机隔空投送后岛上无进行中/完成常驻  
- **根因倾向:** 落点由系统决定（常进「照片」）；与系统 tip 重复；监视 Downloads 覆盖不全  
- **处置:** **已撤回接收上岛**（2026-11-27）；仅保留货架隔空发送；见 PRODUCT §5.17 / §5.18  
- **自动化:** 不强制

### network-link-tip-miss — 切 Wi‑Fi / VPN 无 tip

- **recurring:** false  
- **occurrences:** 1（2026-11-23：默认关 + 仅 `NWPathMonitor`；Clash 系统代理不改 path；空闲 `utun` 误判）  
- **症状:** 切换 Wi‑Fi 或 Clash/VPN 后岛上无网络 tip；日志无 `NetworkLink`  
- **根因倾向:** tip 默认关且启动未拉会话；系统代理通断不走 path；`availableInterfaces` 含常驻 `utun`  
- **防护:** **默认关**；用户打开开关时 `WidgetPermissionGate` 申请定位；启用时 `start`；`SCDynamicStore` 订主接口+Proxies；VPN=主接口隧道 **或** 系统代理  
- **相关代码:** `NetworkLinkSession` / `NetworkLinkMonitor` / `WidgetPermissionGate.location`  
- **自动化:** `NetworkLinkTipPolicyTests`（occurrences=1，不强制每次跑）

### network-link-name-miss — Wi‑Fi / VPN 名称读不到

- **recurring:** false  
- **occurrences:** 2（2026-11-23：日志 `ssid=` 空；同日设置页「允许读取」按钮无弹窗）  
- **症状:** 真机 tip 左翼只有「Wi‑Fi」「VPN」，没有 SSID / 节点名；点授权钮无反应  
- **根因倾向:** Sonoma+ CoreWLAN `ssid` 需定位；仅 `requestWhenInUse` 在 macOS/LSUIElement 常不弹窗；缺 location entitlement；Clash 系统代理不暴露节点名  
- **防护:** location entitlement；`requestWhenInUse` + `requestLocation`；activate App；约 1.2s 仍 notDetermined 则开系统定位页；VPN 记名 + 代理客户端启发式  
- **相关代码:** `NetworkLinkLocationAccess` / `NetworkLinkMetrics` / `NetworkLinkTipWidgetConfigSection`  
- **自动化:** 不强制（occurrences=2 但难自动化系统弹窗，暂不标 recurring）

### system-focus-tip-miss — Focus 开/关无 tip 或无名无图标

- **recurring:** false  
- **occurrences:** 2（2026-11-23：落地时确认公开 API 仅布尔；DoNotDisturb DB 需完全磁盘访问。同日：自定义「你好模式」等 tip 无图标，日志 `symbol=emoji.face.grinning` / `rocket.fill`）  
- **症状:** 切换系统 Focus 后岛上无 tip，或只有笼统文案、无模式名/图标/结束时间；部分模式有名无图标  
- **根因倾向:** 未授完全磁盘访问读不了 `~/Library/DoNotDisturb/DB`；未启动会话；与专注计时混淆；`symbolImageName` 常为**私有** SF Symbol（`emoji.*`、部分内置如 `rocket.fill`），公开 `Image(systemName:)` 空白  
- **防护:** **默认关**；打开开关 / 引导批量开时申请完全磁盘访问；启用时 `start`；未授权不投 tip；与 `FocusTimerSession` 隔离；图标经 `SystemFocusSymbol` 公开→私有 CoreGlyphs→回退  
- **相关代码:** `SystemFocusSession` / `SystemFocusStoreReader` / `SystemFocusSymbol` / `WidgetPermissionGate.fullDiskAccess`  
- **自动化:** `test_systemFocusTip_detailAndOffSymbol`（含私有符号解析；occurrences=2 但未标 recurring——私有 API 依赖系统 glyph 包）

### dock-apps-launcher-blocked — Dock「App」启动台点不开

- **recurring:** false  
- **occurrences:** 1（2026-11-24）  
- **症状:** Dock 上 tooltip「App」的启动台（`Apps.app` / 旧 Launchpad）点击无反应或闪一下被盖住  
- **根因倾向:** Ridge 岛窗 level 高于系统启动台遮罩；`FullscreenMonitor` 虽能侦到 `systemOverlay`，但 `applyFullscreen` 误用 `hideInFullscreen` 开关（默认关）→ 岛不让路  
- **防护:** `IslandFullscreenHidePolicy`：`systemOverlay` **一律**隐藏并 `orderOut`；普通绿钮全屏仍跟设置；启动台 activate 立即重算；窗主 PID 须落在 Apps/Siri/Launchpad bundle  
- **相关代码:** `FullscreenMonitor` / `IslandFullscreenHidePolicy` / `IslandController.applyFullscreen`  
- **自动化:** 不强制（occurrences=1）；`test_islandFullscreenHide_systemOverlayAlwaysHides`

### download-complete-phase-stuck — 下载完成后仍停在「下载中」

- **recurring:** false  
- **occurrences:** 1（2026-11-24）  
- **症状:** 浏览器文件已落盘，岛面仍显示进行中（估速/下载图标），不切「下载完成」  
- **根因倾向:** 临时件 rename 瞬间成品尚未可见就放弃；Chrome `Unconfirmed *.crdownload` 无成品路径提示；失败后 `pending` 仍为 `.downloading`  
- **防护:** 成品解析重试；Unconfirmed/无名靠短窗最新非临时文件；孤儿进行中约 1.2s 兜底切完成或撤；完成路径 warn 落盘  
- **相关代码:** `DownloadCompleteSession.resolveFinalURL` / `scheduleStabilityCheck` / `reconcileOrphanDownloading`  
- **自动化:** 不强制（occurrences=1）；`test_downloadComplete_resolveFinalAfterTempRename`

### widget-library-card-hit-area — 库卡只有内容可点、留白点不中

- **recurring:** false  
- **occurrences:** 1（2026-11-24）  
- **症状:** 小组件库卡片灰舞台外留白 / 卡边点按无反应，须点到预览或标题才进配置  
- **根因倾向:** 舞台、标题、箭头拆成多个小 `Button`，卡根无整卡 `contentShape`  
- **防护:** 整卡一个 `Button` + 圆角 `contentShape`；开关叠在 Button 外，避免连带进详情  
- **相关代码:** `WidgetLibraryCard`（`WidgetsSettingsPane`）  
- **自动化:** 不强制（occurrences=1）

### download-complete-open-wrong-file — 完成后「打开」不是刚下的文件

- **recurring:** false
- **occurrences:** 7（2026-11-24：错文件；进度环；打开失灵；dmg+悬停；整卡 onTap+本地 ⌘O；右翼空 onTap；**同日番茄终局/展开页盖住下载常驻 →「打开」不在树上、整段 `hoverPaused=false` 点穿**）
- **症状:** 点完成岛打开旧同名；SwiftUI 点「打开」无响应；完成态秒收点不到；进度环上下被裁；速度文案变长短导致翼宽抖；点打开出怪异带「取消/打开」的窗；伸手点外部钮岛自己展开；**「打开」钮点不中；焦点在他 App 时快捷键打开系统「打开」面板**
- **根因倾向:** preferred 旧同名；中文未确认；nonactivatingPanel 上 SwiftUI 首击失灵；右翼 `.clipped` 吃描边；速度列 hug 内容；`selectFile` 对 dmg 易误开镜像面板；下载待命未禁悬停展开；整卡/右翼/半岛 `onTapGesture` 盖住 AppKit；本地 ⌘O；**`isExpanded` 时 IslandBody 只画 WidgetHost，下载「打开」未进树；番茄终局 sticky 反复抢展开；点击全程穿透（无 mouseDown）**
- **防护:** 访达 `activateFileViewerSelecting`；完成态右翼禁 SwiftUI tap；全局瞬态热键；**下载常驻抢占：`ensureDownloadCompactClickable` 收起展开页 + 对齐 380 可点区；禁番茄终局 sticky / 悬停展开盖住下载；IslandBody 优先画下载常驻**
- **相关代码:** `DownloadCompactStandbyView` / `DownloadCompleteSession` / `IslandController.ensureDownloadCompactClickable` / `IslandExpandedPanelPolicy.shouldBlockFocusCompletedSticky`
- **自动化:** 不强制；`test_downloadComplete_resolveFinalAfterTempRename` / `test_downloadComplete_openSuppressesHoverExpand`

---

## 变更日志

| 日期 | 变更 |
|---|---|
| 2026-11-24 | 录入 `ui-style-drift` recurring：视觉令牌 + `test_uiStyleLock_*` 钉死，防修行为顺手改样 |
| 2026-11-24 | 选时「正计时」补单测：自适应宽/文案热区/挡媒体/Hosting 优先级；catalog focus-steal +1 |
| 2026-11-24 | 选时「正计时」：HitView+DirectHit；hosting 按钮优先于可编辑外溢；选时中禁媒体抢页；focus-steal |
| 2026-11-24 | 选时「正计时」改 AppKit 整 bounds 可点（SwiftUI 只吃图标）；catalog focus-steal +1 |
| 2026-11-24 | 选时「正计时」：保展开 max(stable,panel) 盖住更宽选时岛；整颗胶囊可点；catalog hover-retention +1 |
| 2026-11-24 | 音乐+正计时：离岛清 hover 恢复数字；时长 Button 热区；trailing 解除去抖；padX≥28；media 用 isActive；catalog media-compact +1 |
| 2026-11-24 | 播放+正计时：Controller 钉右翼 morph、整翼热区、padX≥22；规则 island-hit-targets；catalog media-compact +1 |
| 2026-11-24 | 播放+正计时右翼点空：OpaqueFill 禁命中 + trailing underlap；catalog media-compact +1 |
| 2026-11-24 | 专注终局高=刘海（去掉 tip 底距），catalog `focus-completed-clipped-by-notch` +1 |
| 2026-11-24 | 计时待命左右边距：左 10 / 右 16，躲开下圆角贴边；catalog `focus-timer-standby-side-margins` |
| 2026-11-24 | 正计时左右被裁：收起勿用 Preference 缩窄窗框；文案始终分:秒；岛宽/内边距加大 |
| 2026-11-24 | 正计时待命：禁每秒缩扩 + 按下钉 morph；待命钮恢复 SwiftUI 原貌（勿 AppKit 改长相）；catalog focus-steal / media-compact +1 |
| 2026-11-24 | 计时右翼贴边误收：收起 interactive 外扩 + dualFlush/待命地板；catalog hover-retention / media-compact recurring |
| 2026-11-24 | 四档定稿：A 取色框选；B 会议/播放；C 下载/计时；D tip（PRODUCT + island-priority-grades） |
| 2026-11-24 | 下载：计时并排左下右计；音乐并排左音右下（下完再露计时）；布局矩阵同步 |
| 2026-11-24 | 下载与音乐并排右翼（不再被盖）；布局矩阵/PRODUCT 同步 |
| 2026-11-24 | 下载并排半翼改半岛（底边渐变+悬停打开）；单独仍全岛 |
| 2026-11-24 | 下载打开：常驻抢占收起番茄展开页，打开钮进树可点；catalog `download-complete-open-wrong-file` +1 |
| 2026-11-24 | 下载打开：完成态右翼/半岛去掉空 onTap（仍会抢 AppKit）；catalog `download-complete-open-wrong-file` +1 |
| 2026-11-24 | 下载打开钮：去整卡 tap；完成态全局热键；catalog `download-complete-open-wrong-file` +1 |
| 2026-11-24 | 下载打开：dmg→访达、禁待命悬停掀面板、打开后冷却；catalog `download-complete-open-wrong-file` +1 |
| 2026-11-24 | 库卡/详情预览下圆角跟 `IslandSettings`；catalog `island-bottom-corner-preview-dead` recurring |
| 2026-11-24 | 外设/本机电池/网络/专注库卡 tip 统一 meetingMatchedCompactChrome；catalog `library-island-stage-stretch` +1 |
| 2026-11-24 | 下载快捷键可录制（HotKeyChord + SettingsHotKeyRecorder） |
| 2026-11-24 | 下载设置：点按动作 + 快捷键直达；库卡预览 meetingMatchedCompactChrome |
| 2026-11-24 | 下载完成：AppKit 打开/⌘O、3s 悬停、速度定宽、环不裁；catalog `download-complete-open-wrong-file` +1 |
| 2026-11-24 | 下载：中文未确认 + 拒旧同名 + 访达选中 + 估长进度环；catalog `download-complete-open-wrong-file` +1 |
| 2026-11-24 | 下载完成默认访达选中 + 进度环读浏览器总长；catalog `download-complete-open-wrong-file` |
| 2026-11-24 | 小组件库卡整卡可点进配置（开关除外）；catalog `widget-library-card-hit-area` |
| 2026-11-24 | 浏览器下载岛面方案 04（微圆环+打开徽章） |
| 2026-11-24 | Dock「App」启动台被岛窗盖住：systemOverlay 一律让路，不再绑「全屏时禁用」 |
| 2026-11-24 | 浏览器下载：完成后未切「下载完成」态（rename 竞态/Unconfirmed）；重试解析成品 + 孤儿兜底 |
| 2026-11-23 | 浏览器下载：进行中估速 / 无进度退化图标；`downloadResident` 仍夹在音乐与专注之间 |
| 2026-11-23 | 下载完成常驻：`downloadResident` 权重夹在音乐与专注之间；布局矩阵 64 格 |
| 2026-11-23 | Focus tip 半岛方案 03（模式色光点 / 关态空心环）；C 类 secondary |
| 2026-11-23 | Focus 自定义/私有图标走私有 CoreGlyphs；catalog `system-focus-tip-miss` occurrences=2 |
| 2026-11-23 | 撤回 tip「上线默认开」；网络/Focus 默认关，打开再申请定位/完全磁盘访问 |
| 2026-11-23 | 系统 Focus tip 落地；catalog `system-focus-tip-miss` |
| 2026-11-23 | 网络 tip：定位读 SSID + 代理客户端名回退；catalog `network-link-name-miss` |
| 2026-11-23 | 网络 tip 翼宽锁定 `preparedWingWidth`；补 `wingTipCardsMatchPreparedWingWidth`；catalog double-padding +1 |
| 2026-11-23 | 网络 tip：默认开 + 系统代理/主接口侦测；catalog `network-link-tip-miss` |
| 2026-11-22 | 本机电池 tip：AC 边沿（含优化充电）+ IOPS 监听 + 启动拉起 + 设置试投；catalog `mac-battery-tip-miss-on-ac` |
| 2026-11-22 | 进程结束 tip 自动收按 tip id 撤槽，勿绑旧 `lastWatchEnded`；catalog `process-ended-tip-stale-dismiss` |
| 2026-11-19 | 加厚岛逻辑自动化：全 C 盖专注、权重阶梯、翼宽、`shouldDismissNow`、Center FIFO、专注待命；测试台仍归手动 |
| 2026-11-17 | 免打扰/自动收/收岛策略自动化：`IslandNoticeBehaviorTests` + `IslandNoticeDismissPolicy` |
| 2026-11-17 | 岛展示布局真值表 + tip 契约穷尽：`IslandNoticeLayoutMatrixTests`；catalog `island-notice-layout-matrix` |
| 2026-11-17 | 岛展示权重：取色/框选/会议 > 播放 > 专注 > C；C 暂盖右翼专注，约 3s 后专注回右 |
| 2026-11-17 | 改 RAM 阈值 / 开告警时清免打扰并 rearm，新规则立刻可再提示 |
| 2026-11-17 | 点免打扰立刻撤 RAM tip 并收岛；catalog `ram-mute-tip-stays` |
| 2026-11-17 | RAM tip 对齐原稿：单独紧凑双翼（左 `● % RAM`，右 App 名+`4.1G`、无图标）；悬停右翼免打扰+管理；并排才半块 |
| 2026-11-17 | 瞬时 tip（`expandsDuringSettingsSession`）设置开着也程序 expand，不靠悬停；`pointerOverSettings` 不收 sticky；catalog recurring |
| 2026-11-17 | 设置会话挡住 tip 展开时延后 3s 计时，关闭后补 expand；catalog `settings-session-swallows-transient-notice` |
| 2026-11-14 | 久坐关键路径改 warn 落盘（启动/离开/进度/投递）；catalog `move-reminder-hard-to-trigger` |
| 2026-11-14 | 击键峰值按当日小时桶 max；桶持久化；`KeystrokePeakHourTests`；catalog `keystroke-peak-hour-not-max` |
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
| 2026-11-16 | 引导权限未齐不进自启：`allSelectedPermissionsSatisfied`；catalog `onboarding-perms-skip-ahead` |
| 2026-11-16 | 开蓝牙勿叠弹输入监控：HID 仅 Battery System + 蓝牙未决跳过 HID；catalog `bluetooth-hid-input-monitoring` |
| 2026-11-16 | 屏幕录制：首次 CGRequest 登记列表（不叠开设置）；再点才直开隐私页；catalog `screen-capture-double-prompt` |
| 2026-11-16 | island-focus-steal +1：久坐 +10m 点穿；翼 tip 可点区抬双翼 + 强制保展开；久坐 preemption=50 |
| 2026-11-16 | 提示双槽：A 满岛；B+C 左右；专注待命 C 常驻；短 C 暂占后归还；`test_islandNoticeDualSlots_*` |
| 2026-11-17 | 非专注 C 改 FIFO 队列 + 统一 3s；专注左/短 C 右；`test_islandNoticeDualSlots_secondaryTipsQueueFIFO` |
| 2026-11-27 | shelf-copied-notice-miss +1：去掉剪贴板层 sticky 跳过投递；`copy.*` 与其它瞬时 tip 一样设置库开着仍上岛 |
| 2026-11-16 | shelf-copied-notice-miss +1：设置设计页 sticky↔收起互殴连震；同指纹去抖；notice expand 套圆岛；`test_shelfCopiedNoticeMiss_settingsBlocksStickyForceExpand` |
| 2026-11-16 | shelf-copied-notice-miss +1：播放中复制 dual 误抬会议翼宽整岛黑；`usesDualFlushChrome` + flush 已复制 |
| 2026-11-16 | shelf-copied-notice-miss +1：DualNotchWingRow 禁 GeometryReader（fixedSize 塌宽）；`Surface.dualFlush` 零 inset；右翼仍 Ø32 |
| 2026-11-16 | shelf-copied-notice-miss：双槽右圆岛只填左翼 flush；左宽 148、右 Ø32，勿整条黑框包「已复制」 |
| 2026-11-16 | shelf-copied-notice-miss：双槽非对称 `dualFlushHorizontalOffsetX` 为负，左翼往左伸、刘海空隙对准硬件 |
| 2026-11-16 | tip/双槽与刘海竖缝：Hosting `safeAreaInsets` 顶出内容；`ignoresSafeArea` + 宿主 `safeAreaInsets` 清零 |
| 2026-11-16 | 双槽左右黑底各伸进刘海 `dualFlushNotchUnderlap`（空宽无内容），盖住刘海圆角缺口 |
| 2026-11-16 | 双槽左右小岛统一音乐标准：`bareWingContent` 三区 + 左右同宽 flush；非圆岛双槽左右分填，禁整板黑底/嵌套黑胶囊 |
| 2026-11-16 | 两 B（会议+音乐）只展示会议满岛；再出 C → 左会议右 C + dualFlush；`.dual` 不再抬会议双翼宽 |
| 2026-11-16 | 半块 flush 不得改满岛 tip：会议常显入会钮/原色；AI/外设/专注/音乐满岛色与半块 `flush*` 隔离 |
| 2026-11-16 | 入会链：跳过 Google/Outlook 日程页；先匹配 Zoom 等；钉钉保留原 https；catalog `meeting-join-wrong-calendar-url` |
| 2026-11-16 | 入会后 tip 不消失：先打 dismissed 再撤 tip，避免 tick 竞态；catalog `meeting-tip-stays-after-join` |
| 2026-11-16 | meeting-tip-stays-after-join → recurring：会话级 `dismissedAfterJoinID` + publish 拒投；`test_meetingTipAfterJoin_*` |
| 2026-11-16 | meeting-join-wrong-calendar-url → recurring：扩写 `test_meetingJoinLink_*`（Outlook/腾讯/泛型/Session） |
| 2026-11-14 | OCR 无文字静默收起，不上岛「选区内未识别到文字」；catalog `ocr-empty-notice-noise` |
| 2026-11-14 | 播放中点刘海勿落空态：`dragHold` 先开媒体；catalog `media-click-opens-empty` |
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
