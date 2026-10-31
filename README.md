# Ridge

macOS 灵动岛（Dynamic Island）App。独立仓库，与 Focal / daphnis-apps 分离。

## 技术栈

- Swift + SwiftUI + AppKit（无边框 `NSPanel` 贴刘海）
- XcodeGen（`project.yml`）
- 无自建后端；数据与设置默认本机

## 开发

```bash
chmod +x scripts/relaunch-dev.sh
./scripts/relaunch-dev.sh
```

会编译、结束旧进程、`ditto` 覆盖到 `/Applications/Ridge.app` 并只启动这一份。

进度见 [IMPLEMENTATION.md](IMPLEMENTATION.md)。Agent 约定见 [`.cursor/rules/`](.cursor/rules/)。

## 本机操作

- 指针移到刘海 / 岛上：自动展开；移开后收起
- 菜单栏图标：设置（居中大窗）、退出
- 设置 → 灵动岛：动画速度、全屏隐藏、触觉反馈、录屏可见性
