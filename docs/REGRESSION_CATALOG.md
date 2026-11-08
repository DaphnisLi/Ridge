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
| `settings-preview-live-data` | 设置预览用真数据 | ≥2 | 库卡/详情拉实时源或并排多卡；空数据/网络抖时预览难看 | `widget-preview.mdc`：仅 `WidgetSamplePreview` 假数据；股票预览单卡样张 |

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
- **防护:** `WidgetSamplePreview.island` / `SettingsIslandPreviewCard`；假数据单形态够用即可  
- **自动化建议:** 预览路径不得依赖网络；样张条数断言（如 stocks ≤ 1）

### shelf-copied-notice-miss — 复制成功有时不上岛提示

- **recurring:** false  
- **occurrences:** 1（用户 2026-11-08 反馈）  
- **症状:** 复制文字/链接/颜色/截图后，偶发不出现「已复制」岛提示  
- **根因倾向（待证）:** `showCopiedNotice` 关闭；dismiss/收岛竞态；`IslandNoticeCenter` 短时提示被清掉（代码注释已提示勿先清空再设）  
- **相关代码:** `ClipboardHistoryStore`、`IslandNoticeCenter`、`ShelfSettings.showCopiedNotice`  
- **自动化建议:** 开启开关下模拟写入剪贴板历史 → 断言 present「已复制」；连续两次复制均应可见

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

---

## 变更日志

| 日期 | 变更 |
|---|---|
| 2026-11-08 | 初版：收录悬停热区、边距叠层、预览真数据为重复出现；录入复制提示缺失等 |
| 2026-11-08 | 录入 AI 额度账号作用域提示问题，并修换号嗅探 / 换回再弹 |
