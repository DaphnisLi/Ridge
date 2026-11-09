# Ridge 回归问题目录

本文档记录开发中出现的缺陷与易复发模式，供 Agent 维护，并作为后续**自动化测试**的优先清单。

## 约定

| 项 | 说明 |
|---|---|
| 收录时机 | 修完或用户明确指出后写入；同一根因再出现 → `occurrences` +1 |
| **重复出现** | `occurrences ≥ 2`，须标 `recurring: true`，并列入下方「重复出现问题」表 |
| 自动化 | 后续 XCTest / UI 用例优先覆盖 `recurring: true`；用例 id 建议对齐 `id` 字段 |
| 权威规则 | 维护流程见 `.cursor/rules/regression-catalog.mdc` |

---

## 重复出现问题（occurrences ≥ 2）

| id | 标题 | 次数 | 症状 | 防护 / 测试锚点 |
|---|---|---|---|---|
| `island-hover-retention` | 岛悬停热区退化 | ≥3 | 展开后热区缩成刘海，鼠标下移/拖一下就收岛 | `island-hover-retention.mdc`；`IslandExpandedPanelPolicy` / `RidgeTests`；手测大岛下半截 |
| `island-chrome-double-padding` | 岛边距叠两层 | ≥2 | 内容根再加 padding，与 `IslandChrome` 叠加，下边距过大 | `widget-architecture.mdc` / `island-notice.mdc`：根视图禁止外圈 padding |
| `settings-preview-live-data` | 设置预览用真数据 | ≥2 | 库卡/详情拉实时源；空数据/网络抖时预览难看 | `widget-preview.mdc`：仅 `WidgetSamplePreview` 假数据；股票预览固定两卡假样张 |
| `shelf-copied-notice-miss` | 复制成功提示看不见 | ≥3 | 取色引导后「已复制」投递了但不显示 | present 前 `forcePanelSize` 短条；勿先 dismiss 再 present |

---

## 已记录问题（全量）

### island-hover-retention — 岛悬停热区退化

- **recurring:** true  
- **occurrences:** 3+（历史反复；2026-11-08 货架/纵滑再次触发）  
- **症状:** 大岛仍在，保展开/可点区退成刘海小框；下移、拖动、滚动易误收  
- **根因倾向:** Preference 误报矮框；热区只用 `notchFrame`；翻页缩小窗口写入刘海尺寸  
- **防护:** `IslandExpandedPanelPolicy`、`lastStableExpandedPanelSize`、下沿外扩；改 Island 悬停必读规则  
- **自动化建议:** 展开态 retention 含面板下半截；collapsed-sized panel 时仍用稳定尺寸；拒绝误缩

### island-chrome-double-padding — 岛边距叠两层

- **recurring:** true  
- **occurrences:** 2+（通知卡 / 多 widget 反复翻车）  
- **症状:** 下边距过大，或与设计稿不一致  
- **根因倾向:** 根视图 `.padding(.vertical)` / HTML `py-*` 再叠 `IslandChrome.contentBottom`  
- **防护:** 壳层定外距；widget/通知卡根视图只排内容  
- **自动化建议:** 抽查关键 View 根修饰符；或 snapshot 对比 chrome 后边距

### settings-preview-live-data — 设置预览用真数据

- **recurring:** true  
- **occurrences:** 2（股票库卡多卡真价感；此前其它 widget 同类）  
- **症状:** 无数据/网络失败时预览空或「更新中」；库卡裁切多卡  
- **根因倾向:** 预览直连 Session / 实时源；样张塞满多枚  
- **防护:** `WidgetSamplePreview.island` / `SettingsIslandPreviewCard`；假数据固定形态（股票两卡样张）  
- **自动化建议:** 预览路径不得依赖网络；股票样张条数断言 `== 2`

### library-island-stage-stretch — 库卡黑岛被舞台拉满

- **recurring:** false  
- **occurrences:** 1（2026-11-09：股票库卡直角黑块 + 卡片纵向过长）  
- **症状:** 库卡预览黑岛呈直角高矩形；股票卡被撑高、价签截断  
- **根因倾向:** `WidgetLibraryCard` 对岛施 `maxHeight: .infinity` 且无 `fixedSize(vertical:)`，黑底填满固定舞台高；窄内容未 `hugsContent` 时横向也拉满；`drawingGroup` 易糊掉下圆角  
- **防护:** 库卡岛 `.fixedSize(horizontal: false, vertical: true)` 贴顶；窄 widget（股票等）`hugsContent`；预览股票 `compactChrome`（矮分时、藏日区间）  
- **自动化建议:** 库卡预览岛固有高 < `islandStageHeight`；股票样张宽约两卡固有宽

### shelf-copied-notice-miss — 复制成功有时不上岛提示

- **recurring:** true  
- **occurrences:** 3（2026-11-08 偶发；2026-11-09 取色两次确认：仅 allowShrink 仍竞态看不见）  
- **症状:** 复制文字/链接/颜色/截图后，偶发不出现「已复制」岛提示；取色尤甚  
- **根因倾向:** ① dismiss 后再 present 会先收岛；② **宽翼引导→短「已复制」时 Preference 先于 `allowPanelShrink` 上报并被误缩守卫拒绝，面板卡在引导尺寸（fromW≈407→toW≈179），短条顶距把文案顶出可视区**；③ `showCopiedNotice` 关闭  
- **防护:** `IslandNoticeCenter.present` 对 short tip **先** `prepareShortNoticeLayout`（`forcePanelSize`）再改 `current`；`expand(islandNotice*)` 已展开时也 `allowPanelShrink`；勿先 dismiss 再 present  
- **相关代码:** `IslandNoticeCenter.present`、`IslandController.prepareShortNoticeLayout`、`IslandViewModel.forcePanelSize`  
- **自动化建议:** tip→copy 后 `panelSize` 接近短条；日志应有「强制写入面板尺寸」，不应再出现 replace 窗口内的「忽略展开态面板误缩」

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

---

## 变更日志

| 日期 | 变更 |
|---|---|
| 2026-11-08 | 初版：收录悬停热区、边距叠层、预览真数据为重复出现；录入复制提示缺失等 |
| 2026-11-08 | 录入 AI 额度账号作用域提示问题，并修换号嗅探 / 换回再弹 |
| 2026-11-09 | 录入取色后岛永久穿透假死；修 tip expand 抢前台 + Esc/超时退出 |
