# EasyWork

[![CI](https://github.com/EasyIndie/EasyWork/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyWork/actions/workflows/ci.yml)
[![Release](https://github.com/EasyIndie/EasyWork/actions/workflows/release.yml/badge.svg)](https://github.com/EasyIndie/EasyWork/actions/workflows/release.yml)
[![Version](https://img.shields.io/github/v/release/EasyIndie/EasyWork)](https://github.com/EasyIndie/EasyWork/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**一条命令，配置好你的开发环境。** 纯 Bash，零运行时依赖，macOS / Linux 通用。

---

## 快速开始

```bash
# 安装 CLI（始终取最新 release；同时创建短命令 ew）
curl -sL https://github.com/EasyIndie/EasyWork/releases/latest/download/easywork | bash

# 轻量初始化：Shell 别名 + Git 别名，零交互、零重依赖
ew init
```

> 系统要求：macOS 或 Linux，bash 或 zsh，已安装 curl 和 git。

`easywork` 与 `ew` 完全等价，本文档统一使用 `ew`。

---

## 为什么顺手

- **零交互上手**：`ew init` 不问任何问题，默认只装轻量、可逆的配置。
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
| `uninstall [组件...]` | 卸载组件（不指定则卸载全部） |
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

| 全局选项 | 说明 |
|---|---|
| `--json` | 机器可读 JSON 输出（日志走 stderr；`version`/`status`/`list`/`doctor` 含 `update` 字段） |
| `--dry-run` | 预览变更，不执行 |
| `--yes` `-y` | 跳过确认 |
| `--verbose` `-v` | 详细输出 |
| `--offline` | 禁止联网（跳过下载） |
| `--keep-config` / `--remove-config` | 卸载时保留 / 删除配置 |

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

### AI 工具 (ai-tools)

自动安装 **claude code / codex / pi**（经 npm）；离线模式自动跳过。
可通过 `[ai_tools] install = false` 关闭。

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

## 开发

```bash
make check    # lint + 格式化检查 + 测试
make test     # 运行测试
make dry-run  # 预览安装
```

需要 ShellCheck、shfmt、BATS。AI 编码代理请先阅读 [AGENTS.md](AGENTS.md)；架构与 v2 蓝图见 [DESIGN.md](DESIGN.md)；版本历史见 [CHANGELOG.md](CHANGELOG.md)。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

[MIT](LICENSE) © EasyIndie
