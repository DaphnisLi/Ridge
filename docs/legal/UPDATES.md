# Ridge 更新通道（官网版）

当前 App 内「检查更新」打开发版页：`https://daphnis.app/ridge/releases`。

接入 Sparkle 2 前请完成：

1. 用 Sparkle `generate_keys` 生成 EdDSA 密钥；公钥写入 `Info.plist` → `SUPublicEDKey`。
2. 部署 `appcast.xml` 至 `SUFeedURL`（默认 `https://daphnis.app/ridge/appcast.xml`）。
3. 解决 XcodeGen 对 Sparkle binary SPM 的 `Sparkle-product` embed 问题（或改为手动拷贝 `Sparkle.framework`）。
4. 在 `UpdateService` 中恢复 `SPUStandardUpdaterController` 调用。
