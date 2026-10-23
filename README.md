# EasyWork

[![CI](https://github.com/EasyIndie/EasyWork/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyWork/actions/workflows/ci.yml)
[![Release](https://github.com/EasyIndie/EasyWork/actions/workflows/release.yml/badge.svg)](https://github.com/EasyIndie/EasyWork/actions/workflows/release.yml)
[![Version](https://img.shields.io/github/v/release/EasyIndie/EasyWork)](https://github.com/EasyIndie/EasyWork/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**一条命令，配置好你的开发环境。** Go 静态单二进制，零运行时依赖，macOS / Linux / Windows 通用。

> 产品页：https://easywork.jokerhub.cn/ ｜ 本地预览：`make site`

---

## 快速开始

```bash
# macOS / Linux（Windows 请在 PowerShell 用下方命令，或在 Git Bash 中运行本行）
curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.sh | bash
```

```powershell
# Windows（PowerShell 原生）
irm https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.ps1 | iex
```

```bash
# 轻量初始化：Shell 别名 + Git 别名，零交互、零重依赖
ew init
```

> 系统要求：macOS / Linux / Windows，已安装 curl（Unix）或 PowerShell（Windows）。
> 发布物为静态单文件二进制，终端用户无需任何运行时依赖。

`easywork` 与 `ew` 完全等价，本文档统一使用 `ew`。

---

## 为什么顺手

- **零交互上手**：`ew init` 不问任何问题，默认只装轻量、可逆的配置。
- **跨平台单二进制**：macOS / Linux / Windows 同一套代码，发布静态二进制（Go 引擎）。
- **重活后置**：Vim IDE、Oh My Zsh、花哨提示符全部按需开启，不惊吓、不拖慢。
- **身份零配置可用**：Git 身份自动探测（config → 已有 `git config` → 跳过），缺失也不阻塞。
- **对人和 AI 都友好**：`--json` 机器可读输出、`--offline` 离线模式、声明式 `config.toml`。
- **升级提示**：安装 / 状态检查会提示新版本（`--offline` 或 24h 内自动跳过）。

---

## CLI 使用

```bash
ew <命令> [参数] [选项]
```

| 命令 | 说明 |
|---|---|
| `init` | 轻量初始化（shell + git，零交互） |
| `install [组件...]` | 安装全部组件（或指定组件） |
| `uninstall [组件]` | 卸载组件（不指定则卸载全部） |
| `status` | 查看当前状态（无参数时的默认命令） |
| `doctor` | 环境诊断（依赖 / 网络 / shell） |
| `list` | 列出可用组件 |
| `config` | 查看配置文件 |
| `config get <键>` | 读取配置项 |
| `config set <键> <值>` | 写入配置项（config.toml） |
| `config edit` | 编辑配置文件 |
| `version` | 查看版本 |
| `update` | 升级到最新版本 |
| `completion` | 安装 / 移除 / 查看 shell 补全 |
| `keepawake on/off` | 设备防休眠（合盖仍会睡眠；不改系统电源策略） |

| 全局选项 | 说明 |
|---|---|
| `--json` | 机器可读 JSON 输出（日志走 stderr；`version`/`status`/`list`/`doctor` 含 `update` 字段） |
| `--dry-run` | 预览变更，不执行 |
| `--yes` `-y` | 跳过确认 |
| `--verbose` `-v` | 详细输出 |
| `--offline` | 禁止联网（跳过下载） |
| `--keep-config` / `--remove-config` | 卸载时保留 / 删除配置 |

> **Windows 中文显示**：控制台下直接运行即为 UTF-8 正常显示；管道/重定向时自动转成系统
> ANSI 代码页（兼容 PowerShell 5.1 / cmd）。需要字节级 UTF-8（CI、脚本解析）时设
> `EASYWORK_OUTPUT_ENCODING=utf8`；`--json` 输出始终是 UTF-8。

### 机器可读输出（`--json`）

`status` / `version` / `list` / `doctor` 支持 `--json`：stdout 为纯 JSON、日志走 stderr，便于 AI / 脚本消费。

```jsonc
// ew status --json
{
  "ok": true,
  "command": "status",
  "data": {
    "config": { "path": "/Users/me/.easywork/config.toml", "exists": true, "valid": true },
    "modules": [
      { "name": "shell", "state": "true", "ok": true },
      { "name": "git", "state": "true", "ok": true },
      { "name": "vim", "state": "absent", "ok": false }
    ],
    "update": { "latest": "v1.0.0", "available": true }
  },
  "error": null
}
```

每个响应都遵循 `{ "ok", "command", "data", "error" }` 信封；`data.update` 报告是否有新版本
（`available: true` 时可提示用户运行 `ew update`；`--offline` 时为 `false`）。

---

## 模块

### Shell

适配 zsh / bash，按 `config.toml` 分层开关（**默认保守**）：

- 默认：安全别名（`grep`/`mv`/`cp`/`rm` 加保护参数、`g=git`、`q=exit`、FFmpeg 简写）
- 可选：花哨提示符（含 Git 分支）、Oh My Zsh、macOS 网络 / VPN 工具函数

### Git

身份管理 + 80+ 别名（25 个类别：日志、分支、提交、推送、变基、暂存、工作树、子模块等）。

- 身份支持 personal / work / custom，全局或仓库级
- **无身份也能用**：自动探测，缺失时只装别名
- 别名写入 `~/.gitconfig` 的 managed section，卸载可还原原配置

### Vim

通过 vim-plug 管理 19 个插件，自动安装 Node.js、ripgrep 依赖。

NERDTree、Airline、fzf、coc.nvim、ALE、Markdown 预览、Git 集成等。

### GitHub CLI (gh)

自动安装官方 GitHub CLI，便于在终端完成 PR / issue / release / actions 操作。
旧发行版（默认源无 gh 时）会自动添加 GitHub 官方 apt/dnf 源。

### AI 工具 (ai)

自动安装 **claude code / codex / pi**（经 npm）；离线模式自动跳过。
可通过 `[ai] install = false` 关闭。旧名 `ai-tools` 仍可用作兼容别名。

细粒度选择（多个目标以**空格**分隔）：

```bash
ew install ai             # 全部子工具
ew install ai/claude      # 只装 1 个
ew install claude codex   # 多个（简写）
```

也可用 `[ai] tools = "claude codex"` 设默认子集（不写 = 全部）。

### 可选工具

以下工具**默认不装**（避免 `ew install` 默认装重组件），显式指名才安装；
平台无支持版本时自动跳过。**不装 GUI 应用（终端模拟器除外）**：

```bash
ew install glow        # 终端 Markdown 渲染（全平台）
ew install herdr       # Agent 运行时（全平台）
ew install mole        # macOS 清理与优化（macOS / Windows，命令 mo）
ew install ghostty     # Ghostty 终端（macOS / Linux，终端模拟器）
```

`ew list` 会以「（可选，默认不装）」标注。

---

## 配置

配置文件 `~/.easywork/config.toml`（声明式，AI 可直接生成 / 编辑）：

```toml
schema_version = 1

[shell]
enable_aliases      = true    # 安全别名（默认开）
enable_fancy_prompt = false   # 花哨提示符，默认关
enable_ohmyzsh      = false   # Oh My Zsh，默认关
enable_net_tools    = false   # macOS 网络/VPN 工具，默认关

[git]
identity = "personal"         # personal | work | custom
scope    = "global"           # global | local

[git.identities.personal]
name  = "张三"
email = "zhangsan@example.com"

[git.identities.work]
name  = "San Zhang"
email = "san.zhang@company.com"

[vim]
enabled = true
```

写入方式：

```bash
ew config set git.identities.personal.name "张三"
ew config set git.identities.personal.email "zhangsan@example.com"
ew config edit
```

> 旧版 `~/.easywork/config`（ini）仍可读取；运行 `ew install` 时自动迁移到 `config.toml`。

---

## 卸载

```bash
ew uninstall                 # 保留配置文件
ew uninstall --remove-config # 完全移除
ew uninstall shell           # 只卸载指定组件
```

---

## 实现与迁移

- **引擎**：Go（`cmd/ew` + `internal/*`），静态单文件，macOS / Linux / Windows 同一套代码、
  同一套契约。
- **安装入口**：`bootstrap.sh`（`curl | bash`）下载并安装对应平台二进制。
- **单一引擎**：Bash 实现已于 **0.3.0 退役**（存档 tag `legacy-bash-0.3.0`，
  执行记录见 [docs/RETIREMENT.md](docs/RETIREMENT.md)）；`make retire-check` 断言其不会复活。
- **规格与验收**：语言无关契约见 [docs/spec/](docs/spec/)；验收见
  [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。

## 开发

```bash
make check    # lint + 格式化检查 + go test + conformance + 安装链路
make test     # 黑盒 conformance（Go）
make install  # 安装 Go CLI（Unix: /usr/local/bin 或 ~/.local/bin；Windows: ~/.local/bin + PATH）
make dry-run  # 预览安装
```

需要 ShellCheck、shfmt、BATS。AI 编码代理请先阅读 [AGENTS.md](AGENTS.md)；架构与 v2 蓝图见 [DESIGN.md](DESIGN.md)；版本历史见 [CHANGELOG.md](CHANGELOG.md)。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

[MIT](LICENSE) © EasyIndie
