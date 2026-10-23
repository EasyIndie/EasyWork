# EasyWork

[![CI](https://github.com/EasyIndie/EasyWork/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyWork/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/release/EasyIndie/EasyWork)](https://github.com/EasyIndie/EasyWork/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

开发环境配置工具：用一份 `config.toml` 安装并管理 Shell、Git、Vim、gh 与 AI 工具。
Go 静态单二进制，终端用户零运行时依赖，macOS / Linux / Windows 通用。

产品页 <https://easywork.jokerhub.cn/> ｜ 接口规格 [docs/spec/](docs/spec/)

## 安装

```bash
# macOS / Linux
curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.sh | bash
```

```powershell
# Windows（PowerShell，5.1 与 7 均可）
irm https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.ps1 | iex
```

引导脚本探测 OS/架构、下载对应二进制、**校验 sha256** 后安装到 `/usr/local/bin`（可写时）或
`~/.local/bin`，并创建 `ew` / `easywork` 两个入口。需要固定版本时设置
`EASYWORK_VERSION=0.4.3`；也可从 [Releases](https://github.com/EasyIndie/EasyWork/releases) 手动下载。

## 快速开始

```bash
ew init            # 轻量初始化：shell 别名 + git 别名，零交互
ew install --yes   # 按 config.toml 安装（--dry-run 可先预览）
ew status          # 配置与模块状态
ew doctor          # 依赖 / 网络 / 控制台编码 / 电源策略诊断
```

重复执行是安全的：已经正确的部分不会被重写。

## 命令

| 命令 | 说明 |
|---|---|
| `ew init` | 轻量初始化（shell + git，零交互） |
| `ew install [组件...]` | 安装全部或指定组件；支持 `module/component` 与简写 |
| `ew uninstall [组件]` | 卸载并还原备份；不指定则卸载全部 |
| `ew status` | 配置与各模块状态（无参数时的默认命令） |
| `ew doctor` | 环境诊断 |
| `ew list` | 列出组件（含可选模块标注） |
| `ew config get\|set\|edit` | 读写 `config.toml` |
| `ew keepawake on\|off\|status` | 设备防休眠 |
| `ew completion` | 安装 / 移除 / 查看 shell 补全 |
| `ew version` / `ew update` | 版本与自升级（sha256 校验） |

全局选项：`--json`（stdout 纯 JSON，日志走 stderr）、`--dry-run`、`--yes`、`--verbose`、
`--offline`、`--keep-config` / `--remove-config`。

## 模块

核心模块默认安装：

| 模块 | 内容 |
|---|---|
| `shell` | zsh / bash 适配；默认只开安全别名（`grep`/`mv`/`cp`/`rm` 保护、`g=git`、`q=exit`），提示符、Oh My Zsh、网络工具按需开启 |
| `git` | 身份管理（personal / work / custom，全局或仓库级）+ 80+ 别名；无身份时只装别名 |
| `gh` | GitHub CLI；默认源缺失时自动添加官方 apt/dnf 源 |
| `vim` | vim-plug 管理 19 个插件（NERDTree、Airline、fzf、coc.nvim、ALE…） |
| `ai` | claude code / codex / pi（经 npm）；支持 `ai/claude`、`claude` 等细粒度选择 |

可选模块**默认不装**，显式指名才安装：

```bash
ew keepawake on      # 设备防休眠（见下）
ew install glow      # 终端 Markdown 渲染
ew install herdr     # Agent 运行时
ew install mole      # macOS 清理与优化（macOS / Windows）
ew install ghostty   # 终端模拟器（macOS / Linux）
```

平台不支持的模块会被跳过；不安装 GUI 应用（终端模拟器是唯一例外）。

## 设备防休眠

`ew keepawake` 只注册系统电源断言：macOS `caffeinate -s`、Linux `systemd-inhibit`、
Windows `SetThreadExecutionState`。不需要 sudo，不修改系统电源策略。

```bash
ew keepawake on --persist   # 开启 + 写入开机自启
ew keepawake status         # 五态：active / pending-ac / stale / inactive / unsupported

# 期望  开启 mode=ac persist=on
# 实际  active (pid 75111, backend=caffeinate)
```

- `mode = "ac"`（默认）接电生效、拔电照常节能；`--always` 表示电池也阻止睡眠。
- `status` 校验真实断言（macOS 用 `pmset -g assertions`），不把"进程还在"当作生效。
- `off` 会同时拆除自启单元，避免重启后自己复活。
- **合盖仍会睡眠**，任何工具都无法拦截；长时间任务请保持开盖。

## 配置

`~/.easywork/config.toml`：

```toml
schema_version = 1

[shell]
enable_aliases      = true    # 安全别名
enable_fancy_prompt = false
enable_ohmyzsh      = false
enable_net_tools    = false

[git]
identity = "personal"         # personal | work | custom
scope    = "global"           # global | local

[git.identities.personal]
name  = ""
email = ""

[vim]
enabled = true

[ai]
install = true
# tools = "claude codex"      # 只装子集；留空 = 全部

[keepawake]
enabled = false
mode    = "ac"                # ac | always
display = false               # 连显示器一起防睡
persist = false               # 写入开机自启
```

```bash
ew config set git.identities.personal.email "me@example.com"
ew config edit
```

旧版 `~/.easywork/config`（ini）仍可读，首次 `install` / `config edit` 时自动迁移。

## JSON 输出

`--json` 时 stdout 只有一个信封，日志全部走 stderr：

```jsonc
{
  "ok": true,
  "command": "status",
  "data": {
    "config": { "path": "/Users/me/.easywork/config.toml", "exists": true, "valid": true },
    "modules": [{ "name": "shell", "state": "true", "ok": true }],
    "update": { "latest": null, "available": false }
  },
  "error": null
}
```

Windows 上 `--json` 恒为 UTF-8；人类可读输出在被管道/重定向时转成系统 ANSI 代码页
（兼容 PowerShell 5.1 / cmd），需要字节级 UTF-8 时设 `EASYWORK_OUTPUT_ENCODING=utf8`。

## 开发

```bash
make check        # ShellCheck + shfmt + go test + conformance + 安装链路
make test         # 黑盒 conformance（tests/conformance，71 用例）
make install      # 安装到 PATH
make site         # 本地预览产品页 http://127.0.0.1:8765/
make acceptance   # 全量验收（含交叉编译与退役不变量）
```

需要 Go 1.22+、ShellCheck、shfmt、BATS。Bash 引擎已于 0.4.0 退役
（存档 tag `legacy-bash-0.3.0`，见 [docs/RETIREMENT.md](docs/RETIREMENT.md)）。

文档：[接口规格](docs/spec/) · [验收](docs/ACCEPTANCE.md) · [回滚](docs/ROLLBACK.md) ·
[更新日志](CHANGELOG.md) · [贡献](CONTRIBUTING.md) · [AGENTS](AGENTS.md)

---

[MIT](LICENSE) © EasyIndie
