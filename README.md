# CodexAppBar

A macOS menu bar app for managing multiple ChatGPT/Codex accounts. Switch accounts instantly and monitor quota usage without opening a browser.

> **中文说明见下方 / Chinese version below**

---

![CodexAppBar English](en.png)

## Features

- **Multi-account management** — Add unlimited ChatGPT accounts via OAuth
- **Quota monitoring** — Tracks both the 5-hour rolling window and the weekly quota in real time
- **Account switching** *(experimental)* — Writes the selected account to `~/.codex/auth.json`; requires quitting Codex.app to take effect. If using subagents, prefer logging out from within Codex.app instead
- **Auto refresh** — Active account refreshes every 10 seconds while the menu is open; all accounts refresh every 5 minutes in the background
- **Status indicators** — Color-coded badges and menu bar icon reflect account health (normal / warning / quota exhausted / suspended)
- **Animated UI** — Progress bars and percentages animate on update

## Supervisor Automation

This repository also includes a local quota supervisor workflow for unattended use:

- `quota-watcher.py` on the Desktop monitors the active account and waits for Codex to become idle before switching
- `codexbarctl` exposes local control commands for status, account listing, refresh, and safe switching
- the supervisor can maintain a task ledger and resume queued work after a switch

See [README-supervisor.md](README-supervisor.md) for the full operator guide, task examples, and the recommended way to describe tasks to another agent.

## Requirements

- macOS 13 Ventura or later
- [Codex](https://github.com/openai/codex) desktop app installed at `/Applications/Codex.app`

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/yourname/codexBar.git
   ```
2. Open `codexBar.xcodeproj` in Xcode 15+
3. Select your development team in **Signing & Capabilities**
4. Build and run (`⌘R`)

## Usage

1. Launch CodexAppBar — it appears in the menu bar
2. Click **+** to add a ChatGPT account via OAuth
3. Click **切换 / Switch** on any account to activate it; CodexAppBar will confirm and then restart Codex.app
4. The menu bar icon reflects the active account's status:
   - `terminal.fill` — normal
   - `bolt.circle.fill` — quota nearing limit (≥ 80%)
   - `exclamationmark.triangle.fill` — weekly quota exhausted
   - `xmark.circle.fill` — account suspended

## How it works

CodexAppBar uses the same OAuth client ID as the official Codex desktop app to authenticate with `auth.openai.com`. After login, tokens are stored locally in the app sandbox and the active account's tokens are written to `~/.codex/auth.json` for the Codex CLI/app to consume.

Usage data is fetched from the internal `chatgpt.com/backend-api/wham/usage` endpoint.

## Disclaimer

This project is **not affiliated with or endorsed by OpenAI**. It uses unofficial internal APIs that may change or break without notice. Use at your own risk. Do not use this tool to violate OpenAI's [Terms of Service](https://openai.com/policies/terms-of-use).

## License

[MIT](LICENSE)

---

## 中文说明

![CodexAppBar 中文](zh.png)

CodexAppBar 是一个 macOS 状态栏应用，用于管理多个 ChatGPT/Codex 账号，支持一键切换并实时监控额度。

### 功能

- **多账号管理** — 通过 OAuth 添加任意数量的 ChatGPT 账号
- **额度监控** — 实时显示 5 小时滚动窗口用量和周额度
- **账号切换**（实验性）— 将选中账号写入 `~/.codex/auth.json`，需退出 Codex.app 后生效。使用 subagent 时建议通过软件内退出登录功能切换账号
- **自动刷新** — 菜单打开时活跃账号每 10 秒刷新；后台每 5 分钟刷新所有账号
- **状态指示** — 彩色徽章和状态栏图标直观反映账号状态（正常 / 即将用尽 / 额度耗尽 / 已停用）

### 无人值守 Supervisor

这个仓库现在还配套了一套本地额度守卫工作流：

- 桌面的 `quota-watcher.py` 会持续监控当前活跃账号
- 触发阈值后不会立刻切号，而是等待 Codex 空闲再安全切换
- `codexbarctl` 提供本地控制入口，方便外部 agent 调用
- supervisor 可以维护任务账本，并在切号后恢复待执行任务

完整的使用说明、给 Azine 下任务的话术模板、任务数据结构和操作示例见 [README-supervisor.md](README-supervisor.md)。

### 系统要求

- macOS 13 Ventura 及以上
- 已安装 [Codex](https://github.com/openai/codex) 桌面版（位于 `/Applications/Codex.app`）

### 安装

1. 克隆本仓库
2. 用 Xcode 15+ 打开 `codexBar.xcodeproj`
3. 在 **Signing & Capabilities** 中选择你的开发者账号
4. 编译运行（`⌘R`）

### 免责声明

本项目**与 OpenAI 无任何关联**，使用了非官方内部 API，可能随时失效。请勿用于违反 OpenAI 服务条款的行为，风险自担。
