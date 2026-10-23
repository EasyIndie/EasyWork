# 跨平台行为规格（macOS / Linux / Windows）

> 规格编号：C7 ｜ 状态：冻结
> 目的：固定各平台的行为差异边界，保证“一套代码、契约统一”。

## 支持矩阵

| 模块 / 能力 | macOS | Linux | Windows | 说明 |
|---|---|---|---|---|
| `shell` | ✅ bash/zsh | ✅ bash | ✅ PowerShell | Unix 写 `~/.sh_config_custom` 并 source；Windows 直接向 `$PROFILE` 注入 |
| `git` | ✅ | ✅ | ✅ | 写 `~/.gitconfig`（Windows 同路径语义） |
| `gh` | ✅ brew | ✅ apt/dnf/… | ✅ winget/scoop/choco | 包 ID 按平台映射 |
| `vim` | ✅ | ✅ | ✅ | 配置路径见下 |
| `ai`（`ai-tools`） | ✅ npm | ✅ npm | ✅ npm | 需 Node.js/npm |
| `mole`（可选） | ✅ brew | ➖ | ✅ PowerShell | 仅 macOS / Windows |
| `herdr`（可选） | ✅ brew | ✅ brew/脚本 | ✅ PowerShell | 官方 `install.sh` / `install.ps1` 回退 |
| `glow`（可选） | ✅ brew | ✅ 包管理器 | ✅ winget/scoop/choco | 终端 Markdown |
| `ghostty`（可选） | ✅ cask | ✅ 发行版包 | ➖ | 终端模拟器（允许的 GUI 例外） |
| `completion` | ✅ | ✅ | ➖（待实现） | 见未完成清单 |
| `update` 自升级 | ✅ | ✅ | ➖（待实现） | |

## 平台差异与适配

| 维度 | macOS / Linux | Windows | 约定 |
|---|---|---|---|
| 状态根 | `HOME/.easywork` | `HOME\.easywork` | `EASYWORK_HOME` 可覆盖；JSON 展示统一 `/` |
| Shell profile | `~/.zshrc` / `~/.bash_profile` / `~/.bashrc` | `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` | 直接注入 managed section |
| Vim 配置 | `~/.vimrc` | `~/_vimrc` | `Env.VimConfigPath()` |
| Vim 运行时 | `~/.vim` | `~/vimfiles` | `Env.VimPluginDir()`；vim-plug → `<pluginDir>/autoload/plug.vim` |
| 包管理器 | brew / apt / dnf / yum / pacman / zypper / apk | winget / scoop / choco | `PackageManager`；逻辑名 → 平台包 ID |
| `gh` 包 ID | `gh` | winget:`GitHub.cli` / choco:`gh` / scoop:`gh` | `PackageManager.PackageName("gh")` |
| ripgrep 包 ID | `ripgrep` | winget:`BurntSushi.ripgrep.MSVC` | |
| Node 包 ID | `node` | winget:`OpenJS.NodeJS.LTS` | |
| glow 包 ID | `glow` | winget:`charmbracelet.glow` / scoop:`glow` / choco:`glow` | `PackageManager.PackageName("glow")` |
| ghostty 安装 | brew `--cask ghostty` | — | `PackageManager.InstallCask`；macOS 幂等检测 `/Applications/Ghostty.app` |
| 并发锁 | `O_CREATE｜O_EXCL` | 同 | 跨平台一致（不再依赖 flock） |
| 原子写 | temp + rename | temp + rename（覆盖） | `Platform.AtomicWrite` |
| 可执行解析 | `PATH` | `PATH` + `PATHEXT` | `exec.LookPath` |
| 换行 | LF | LF | 统一 LF（工具均可解析） |
| 控制台编码 | UTF-8 直出 | 启动切 CP=65001 并在退出还原 | 控制台直出 UTF-8；**管道/重定向且启动 CP≠65001 时，人类可读输出转系统 ANSI 代码页**（PowerShell 5.1 / cmd 按 OEM 解码管道）；`--json` 恒为 UTF-8 |
| 输出编码覆盖 | — | `EASYWORK_OUTPUT_ENCODING=utf8\|oem` | CI/脚本需要字节稳定时置 `utf8` |
| ANSI 颜色 | 终端原生 | 启动时开启 `ENABLE_VIRTUAL_TERMINAL_PROCESSING` | 不支持时静默跳过 |
| `doctor` 检查 | curl/git/awk/sed/zsh/network | git/curl/node/npm/network | 按平台生成 |

## 工具依赖（用户侧）

| 工具 | 用途 | 是否必需 |
|---|---|---|
| `git` | git 模块身份/别名基础；引导 | 必需 |
| `curl` | Unix 管道安装/下载 | Unix 必需；Windows 用系统 `curl.exe` 或 PowerShell |
| `node` / `npm` | `ai` 安装 claude/codex/pi | 可选（缺失仅跳过并提示） |
| `unzip` 或 `tar` | 引导脚本解压 | Windows 至少其一（系统自带 `tar.exe`） |
| 包管理器 | `gh`/`vim` 依赖安装 | 可选 |

> Go 引擎自身仅依赖标准库，下载用内置 HTTP 客户端，**不要求 curl**；`doctor` 中 curl 为兼容/引导检查项。

## 验收（C7）

- `C7-json-path-slash`：Windows 上 `status --json` 的 `config.path` 使用 `/`（跨平台一致）。
- `C7-vim-paths`：Windows 写 `_vimrc` 与 `vimfiles/`；Unix 写 `.vimrc` 与 `.vim/`。
- `C7-pkg-map`：`PackageName` 映射（winget `GitHub.cli` 等）。
- `C7-doctor`：Windows 不检查 awk/sed/zsh；Unix 检查。
- `C7-console`：`doctor` 报告 `console` 项（Windows 为 `cp=65001`，Unix 为 `utf-8 (n/a)`）。
- `C7-win-output`：Windows 管道下人类输出按 ANSI 代码页编码；`--json` 与 `EASYWORK_OUTPUT_ENCODING=utf8` 下恒为 UTF-8。

## `gh` 安装回退

- 优先使用发行版默认源（`apt-get install gh` / `dnf|yum install gh`）。
- Debian/Ubuntu 默认源缺失：写入 `/etc/apt/keyrings/githubcli-archive-keyring.gpg`，
  并在 `/etc/apt/sources.list.d/github-cli.list` 添加官方源后重试。
- RHEL 系默认源缺失：`config-manager --add-repo`（dnf4/yum）或
  `config-manager addrepo --from-repofile=`（dnf5）后 `install gh --repo gh-cli`。
- macOS/Windows：`brew` / `winget(GitHub.cli)` / `scoop` / `choco`。
