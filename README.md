# CodexHUD

CodexHUD 是一个轻量的 macOS 菜单栏工具，用来把 Codex 的 5 小时窗口和 Weekly 用量直接常驻显示在菜单栏上。

它的核心目标很简单：

> 不用点开 Codex，不用进入 CLI，也不用打开复杂面板，就能一眼看到 Codex 额度状态。

## 🍎 macOS 安装说明

从 [GitHub Releases](https://github.com/shcw0405/CodexHUD/releases/latest) 下载 macOS 版本，解压后将应用拖入 **Applications（应用程序）** 文件夹，然后双击运行。

当前下载包适用于 Apple Silicon（M 系列芯片）Mac。读取余量需要本机已安装 Codex CLI，并通过 ChatGPT 账号登录。

### 首次打开提示“无法验证开发者”怎么办？

由于当前 macOS 版本暂未使用 Apple Developer ID 进行签名和公证，首次运行时 macOS 可能会提示：

> 无法打开，因为无法验证开发者
>
> 或
>
> Apple 无法检查其是否包含恶意软件

这是 macOS Gatekeeper 对未公证应用的正常提示，不代表应用安装失败。请确认应用来自本项目的 GitHub Releases，并在信任来源后继续。

请按照以下步骤操作：

1. 首先尝试打开一次应用，并关闭弹出的提示窗口。
2. 打开 **系统设置**。
3. 进入 **隐私与安全性**。
4. 向下滚动到“安全性”区域。
5. 找到关于本应用被阻止运行的提示。
6. 点击 **仍要打开（Open Anyway）**。
7. 在弹出的确认窗口中再次点击 **打开**。

如果系统要求验证，请使用 Touch ID 或输入 Mac 登录密码。

完成一次后，macOS 通常会记住你对这个版本的选择，之后即可像普通应用一样直接打开。更新版本或系统安全策略变化时，可能需要重新确认。

> 💡 如果在“隐私与安全性”中没有看到“仍要打开”，请先再次双击运行一次应用，再回到该页面查看。

## Preview

![CodexHUD menu settings](CodexHUD/assets/menu-settings.png)

可选悬浮 HUD：

![CodexHUD floating HUD](CodexHUD/assets/floating-hud.png)

## Features

### v0.1.2 界面优化

- 设置菜单、状态和重置倒计时改为中文，保留 CDX、5H、W 等紧凑标记。
- 悬浮窗小 / 中 / 大采用明显区分的尺寸，字号和留白同步缩放，数值居中。
- 悬浮窗跟随已用 / 剩余设置；同时显示两组用量时，各自显示重置倒计时。
- 记住悬浮窗位置和隐藏状态，可右键悬浮窗打开设置。
- 菜单打开时仍可自动刷新，网络请求等待时间增加到 15 秒，超时提示更准确。

- 菜单栏直接显示 Codex 用量，例如 `Cdx 42/18` 或 `Cdx ⚠ 100/51`
- 支持 5-hour rolling window
- 支持 Weekly usage window
- 支持已用百分比 / 剩余百分比切换
- 支持 Full / Compact / Minimal 菜单栏显示模式
- 支持 10s / 30s / 60s / 5m 刷新频率
- 支持可选悬浮 HUD：5-hour / Weekly / Both
- 支持悬浮 HUD 尺寸、背景透明度、文字透明度设置
- 支持隐藏 / 显示悬浮窗口
- 点击菜单栏可查看重置倒计时、更新时间、账号、Plan、数据源
- 支持手动刷新
- 支持错误状态：`Cdx ?`
- 支持数据过期状态：`Cdx stale`

## Data Source

CodexHUD 不使用 mock 数据。

当前版本通过本机 Codex CLI 的 app-server JSON-RPC 读取真实用量：

```sh
codex -s read-only -a never app-server
```

调用的 RPC 方法：

```text
account/rateLimits/read
account/read
```

字段映射：

| Codex RPC 字段 | CodexHUD 含义 |
| --- | --- |
| `rateLimits.primary` | 5-hour window |
| `rateLimits.secondary` | Weekly window |
| `usedPercent` | 已用百分比 |
| `windowDurationMins` | 窗口长度 |
| `resetsAt` | 重置时间 |

## Privacy

CodexHUD 以本地使用为主：

- 不上传 Codex 用量数据
- 不上传 prompt
- 不上传代码内容
- 不读取 Codex session 日志
- 不读取浏览器 cookies
- 不直接读取 `auth.json`
- 仅通过本机已安装的 Codex CLI app-server 获取用量

## Build

```sh
cd CodexHUD
make test
make build
```

构建完成后，App 位于：

```text
CodexHUD/.build/CodexHUD.app
```

## Run

```sh
cd CodexHUD
make run
```

或者直接打开：

```sh
open -n CodexHUD/.build/CodexHUD.app
```

## Verify The Codex RPC

```sh
cd CodexHUD
make probe
```

如果可用，会输出类似：

```json
{
  "planType": "plus",
  "primary": {
    "usedPercent": 42,
    "windowDurationMins": 300
  },
  "secondary": {
    "usedPercent": 18,
    "windowDurationMins": 10080
  }
}
```

## Current Scope

第一版专注菜单栏直显、真实 RPC 取数和轻量悬浮 HUD。自动更新、Homebrew 安装、多账号管理和历史趋势图会留到后续版本。
