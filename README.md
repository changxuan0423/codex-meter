# Codex Meter

原生 macOS 菜单栏额度小工具，适用于 macOS 13 及以上。

## 一行安装

```sh
curl -fsSL https://raw.githubusercontent.com/changxuan0423/codex-meter/main/install.sh | bash
```

支持 Apple Silicon 和 Intel Mac。安装命令下载 GitHub Releases 中的通用版应用、核验 SHA-256 和应用签名，将其安装到 `~/Applications/Codex Meter.app`，然后自动启动。再次运行同一条命令即可更新；不需要 sudo、Swift 开发环境或 API Key。

使用前请在 Codex CLI 或 Codex/ChatGPT 桌面应用中登录 ChatGPT 账户。应用读取该 CLI 的现有额度数据。

也可以从 [Releases](https://github.com/changxuan0423/codex-meter/releases/latest) 下载 `CodexMeter-macos-universal.zip`，解压后放入「应用程序」并打开。应用采用 ad-hoc 签名，尚未进行 Apple Developer ID 签名和公证；如果系统阻止打开，可在确认下载来源后到「系统设置 → 隐私与安全性」查看系统提供的打开选项。安装脚本不会关闭 Gatekeeper 或移除系统安全属性。

## 菜单栏显示

菜单栏示例：`✺ 44% ↻14:00`。百分比表示 **Codex 账户的 5 小时窗口剩余量**，时间是本机时区的下次重置时刻。图标是参考截图绘制的花形终端符号，会随系统明暗模式变化。

菜单栏由原生 NSStatusBarButton 排版，使用经过截图字形校准的 13pt SF 常规字重与等宽数字。花形终端图标为正常菜单栏使用的 16pt，占位宽度随之增加，图标到首位数字的可见空隙保持 8px（2x）。使用系统文字颜色及模板图标颜色，不额外调淡时间。校准方法与历史对抗性审查见 [STYLE_AUDIT.md](STYLE_AUDIT.md)。

## 运行

双击 `build/Codex Meter.app`。应用仅出现在屏幕顶部菜单栏，不占 Dock。点击菜单栏图标查看详情、每周剩余量、刷新、隐藏重置时间、设置开机启动或退出。弹窗在菜单栏下方展开，并限制在当前屏幕的可见区域内；屏幕高度不足时支持滚动，点击外部或按 Esc 关闭。

如需固定安装，将应用复制到用户的 `~/Applications` 或系统「应用程序」文件夹后启动。开机启动默认关闭，安装后可在面板中打开；如果 macOS 要求批准，在系统设置的「通用 → 登录项」中确认。

已有应用运行时，重复打开不会创建第二个图标。MacBook 刘海或菜单栏空间不足时，可在其他应用较少的桌面环境查找该图标，或关闭「菜单栏显示重置时间」节省宽度。

## 数据来源与刷新

- 使用本机 Codex 的现有登录状态，通过 [官方 App Server 协议](https://developers.openai.com/codex/app-server) 的 `account/rateLimits/read` 查询。
- 只读取额度，不创建会话、不发送模型请求、不消耗推理额度；不直接读取、复制或记录登录令牌，不保存账户额度历史。
- 优先查找 `rateLimitsByLimitId.codex`，兼容旧 `rateLimits`，在 primary/secondary 中按 `windowDurationMins == 300` 识别 5 小时额度，按 10080 识别每周额度。
- 剩余量 = `100 - usedPercent`，四舍五入显示整数。所有模型共享哪个计费窗口以 Codex 服务实际返回为准。
- 每 2 分钟刷新一次，唤醒后刷新，也可手动刷新。读取最多等待 25 秒。每次读取后关闭自己的 app-server 子进程。
- 网络出错保留上次结果，同时显示 `!` 和错误说明。超过 5 分钟未更新视为过期。已到重置时刻时显示 `--%`，至少间隔 30 秒查询，获得新结果后才显示百分比。
- 服务未提供 300 分钟窗口时显示 `--%`，不会拿每周额度代替。未知重置时间显示 `--:--`。

默认识别 Codex.app、ChatGPT.app 内置 CLI、Homebrew 和常见 PATH。可通过环境变量 `CODEX_METER_CLI` 指定 CLI 的绝对路径。应用在 Finder 中启动时的 PATH 可能与终端不同。

CLI 需要已登录 ChatGPT 账户，只有 API Key 的配置无法提供订阅额度。若应用提示登录，请在它使用的 Codex CLI/桌面应用完成 ChatGPT 登录后刷新。多个 Codex 配置或账户并存时，以所用 CLI 的现有身份为准。

## 开发与验证

仅依赖 Apple Command Line Tools 和系统 AppKit、SwiftUI、ServiceManagement，无第三方包。

```sh
bash scripts/build.sh
bash scripts/test.sh
"build/Codex Meter.app/Contents/MacOS/CodexMeter" --diagnose
```

`--diagnose` 只输出剩余百分比、重置时间戳和 CLI 是否存在，不输出凭据或账号标识。构建产物按当前 Mac 的架构编译并作本地 ad-hoc 签名，未作 Apple Developer ID 签名或公证；用于当前机器本地运行。对外分发需自行签名和公证。

构建 Apple Silicon + Intel 通用安装包：

```sh
bash scripts/package-release.sh
```

输出 `build/release/CodexMeter-macos-universal.zip` 与 `SHA256SUMS`，发布新 GitHub Release 时同时上传这两个文件。安装脚本默认下载最新发布版，可通过 `CODEX_METER_VERSION=v1.0.5` 固定版本。`CODEX_METER_INSTALL_DIR` 可指定安装目录，`CODEX_METER_SKIP_LAUNCH=1` 可用于验证安装包而不启动应用。

源码结构：`Sources/Quota.swift` 负责数据解析，`Sources/CodexClient.swift` 负责 stdio JSON-RPC，`Sources/PanelPlacement.swift` 计算屏幕边界内的弹窗位置，`Sources/main.swift` 负责菜单栏和设置面板。`Resources/Info.plist` 设置后台菜单栏应用属性。
