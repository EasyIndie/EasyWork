# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与
[语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 修复

- **`ew doctor` 在台式机 / 虚拟机上丢失 `sleep-policy` 检查**：原实现要求 `pmset -g custom`
  同时提供 AC 与电池两个分支，否则整项跳过；Mac mini/Studio/iMac 与 CI 虚拟机只有
  `AC Power:` 分支，因此这项诊断从未生效（GitHub macOS 虚拟机上的 CI 一直因此红灯）。
  现在按分支是否存在分别诊断并回显（`AC` 在前、`Battery` 在后），`sleep=0` 仍不判为矛盾
- **conformance 的 `sleep-policy` 用例改为注入假 `pmset`**：原先直接断言宿主 `pmset` 输出，
  随 CI 机型漂移而失败；现覆盖「两侧」「仅 AC（台式机）」「矛盾组合」三组确定性用例

### 变更

- **CI 分层 + 单次快速迭代**：新增 `Changed paths` 判定与 `Quick gate`（Ubuntu，~1–2 分钟，
  含 ShellCheck / `bash -n` / shfmt / `gofmt` / `go vet` / `go test` / conformance）；
  PR 只跑快车道，重矩阵（macOS ShellCheck、macOS/Windows conformance + Windows 原生冒烟、
  三平台安装链路 e2e、6 目标交叉编译）仅在 `main` 推送且确有代码改动时运行，
  纯 docs/site/markdown 提交自动跳过；`workflow_dispatch` 支持 `scope=fast|full`；
  同分支新推送取消旧运行；重矩阵 `needs: quick`，红灯不再浪费平台机时
- 新增 `make quick`（本地 < 1 分钟门禁）与 `docs/ITERATION.md`（分层门禁、单次快速迭代、
  提交/分支/发布规范）；`CONTRIBUTING.md`、`AGENTS.md`、`docs/ACCEPTANCE.md` 同步
- conformance 用例数 71 → 73

## [0.4.4] - 2026-10-23

### 新增

- **产品页**：`site/` 纯静态单页（无框架、无外链字体/图片、亮暗随系统），
  GitHub Pages 部署到 <https://easywork.jokerhub.cn/>（自定义域名 + 强制 HTTPS）；
  含安装命令一键复制、真实终端输出、命令参考、防休眠说明。`make site` 可本地预览

### 修复

- `ew keepawake on` 成功后 `ew status` 仍显示 keepawake「未安装」：现在同步写入
  manifest 的 `[keepawake] installed=true`（无 manifest 时按需创建；`--dry-run` 不写盘）
- 产品页命令过长时被横向滚动条压住文字：安装命令改为「标签 + 复制」在上、命令独占一行，
  代码块改用 `pre-wrap` 自动换行（复制内容仍是单行命令），不再出现横向滚动条

### 变更

- **文档精简并与实现对齐**：README 重写（安装 / 命令 / 模块 / 防休眠 / 配置 / JSON / 开发）；
  ACCEPTANCE 收敛为当前验收项（188 → 55 行）；DESIGN 压缩至 495 行（796 → 495，
  去掉重复的 Bash API 描述与过期状态表）；AGENTS 增加文档地图
- 删除文档中并不存在的 `ew apply`：`docs/spec/04` 去掉该行，`docs/spec/08` 改为
  `ew install keepawake`（install 即幂等收敛）
- 产品页视觉：首屏两栏、标题层级与间距统一、终端块区分提示符/输出/状态符号、
  hairline 分隔与层级（去掉卡片网格与大写 eyebrow）

## [0.4.3] - 2026-10-23

### 变更

- `ew doctor` 的 `sleep-policy` 同时报告 **AC 与电池**两侧（此前只看当前电源分支，
  插电时看不到电池侧的矛盾），问题按分支标注

## [0.4.2] - 2026-10-23

### 新增

- `ew doctor` 新增 `sleep-policy` 检查（仅 macOS）：检测 `pmset` 的
  `displaysleep >= sleep`、`sleep > 0 && disksleep == 0` 这类"设了但不生效"的矛盾组合
  （`pmset` 只告警、照写），并回显当前电源分支的实际值。只读，不改系统策略。

## [0.4.1] - 2026-10-23

### 修复

- `keepawake`：`on --persist` 未等自启单元真正登记断言就返回，导致紧随其后的
  `ew keepawake status` 在 2–3 秒内误报 `inactive`/`stale`（LaunchAgent/systemd
  启动与断言登记是异步的）。现在会轮询到断言确认（最长 5s）再返回。

## [0.4.0] - 2026-10-23

引擎收敛为 Go 单实现（0.3.0 为最后一个双引擎版本，Bash 资产随该版本发布）。

### 移除

- **Bash 引擎退役**（存档 tag `legacy-bash-0.3.0`）：删除 `bin/easywork`、`lib/*.sh`、
  `MODULES`、`easywork.conf.example` 与 Bash 白盒测试（192 用例）。`bootstrap.sh` /
  `bootstrap.ps1` 成为唯一安装入口；conformance、CI、release 收敛为只针对 Go。
  `make retire-check` 守护不变量，详见 `docs/RETIREMENT.md`。

### 变更

- `bootstrap.sh` / `bootstrap.ps1` 新增 sha256 完整性校验（缺失 checksums 时告警跳过）
- `make check` 收敛为 `lint + fmt-check + gotest + conformance + install-e2e`；
  新增 `make install-e2e`（`bootstrap-e2e` + `update-e2e`，本地镜像不触网）
- CI：新增 Windows 安装链路端到端（`bootstrap.ps1`），`install-e2e` 覆盖三平台；
  Windows 在 **PowerShell 5.1 与 PowerShell 7** 两个宿主下各跑一次（含 `irm | iex` 用法）

## [0.3.0] - 2026-10-23

### 新增

- **设备防休眠 `keepawake`（可选模块 + `ew keepawake on/off/status`）**：
  只注册电源断言（macOS `caffeinate -s` / Linux `systemd-inhibit` / Windows
  `SetThreadExecutionState`），**不改系统电源策略、不需要 sudo**；`mode=ac` 让笔记本
  「接电不睡、拔电照常睡」，`--persist` 写 LaunchAgent / systemd 单元 / 计划任务。
  `status` 区分 `active`/`pending-ac`/`stale`/`inactive`/`unsupported`，不谎报。
- **Windows 中文输出编码修复**：启动时把控制台代码页切到 UTF-8(65001) 并开启 ANSI 转义，
  退出时还原；输出被管道/重定向且启动代码页非 UTF-8 时，人类可读输出转成系统 ANSI
  代码页（PowerShell 5.1 / cmd 按 OEM 解码管道，此前中文全为乱码）。`--json` 恒为 UTF-8，
  `EASYWORK_OUTPUT_ENCODING=utf8|oem` 可显式覆盖；`ew doctor` 新增 `console` 诊断项（显示 `cp=`）。
  Windows 真机验证（11 24H2 / PS 5.1 / SSH）：`.ps1` + `-File` 执行、`CREATE_NO_WINDOW`
  且脱离 SSH 的 Job 对象、`tasklist` 判定存活、参数变更自动重启后端。
  新增 owned-file 写盘原语（`engine.ApplyOwnedFile`）。规格见 `docs/spec/08-keepawake.md`（C11）

## [0.2.x] — 跨平台引擎（Go）

将引擎从 Bash 迁移到 Go，实现「一套代码 + 原生 Windows + 跨平台二进制发布」，
同时保留 Bash 实现作为迁移期等价性 oracle（0.2.0 / 0.2.1）。详见 `DESIGN.md §12` 与 `docs/spec/`。

### 新增

- **`docs/spec/`**：5 个契约的规范性语言无关规格 + managed section 文件协议（C1–C6）
- **Go 引擎**：`cmd/ew` + `internal/{platform,engine,modules,cli,logx}`，静态单文件
- **黑盒 conformance**：`tests/conformance/`（57 用例：C1–C10 + G1/G2 Go-only），同时验证 Bash 与 Go
- **跨平台 CI**：PR/push 跑 `cross-compile`（6 目标）、`gofmt`/`go vet`；
  `go-engine` 三平台（Windows 原生 + **Go-only conformance**，Unix-only 用例自动 skip）
- **Windows 一键安装**：新增 `bootstrap.ps1`（`irm ... | iex`，PowerShell 5.1/7 真机实测通过）
  → 安装 `ew.exe`/`easywork.exe` 并配置用户 PATH/PATHEXT
- **升级修复**：Bash `update` 资产路径修正（`/bin/easywork` → `/easywork`，此前 404 失效）；
  Go `update` 在 Windows 同步更新 `ew.exe`/`easywork.exe` 两个别名
- **release 文案**：更新为 Go + 三平台 + 双一行命令；版本 `internal/version/version.go` → `0.2.0`
- **`make install` 跨平台**：委托 `scripts/install.sh`——Unix → `/usr/local/bin`（否则 `~/.local/bin`）；
  Windows → `~/.local/bin` 的 `easywork.exe`+`ew.exe`，并确保用户 **PATH**/**PATHEXT**（`.EXE`）
- **Windows 原生**：PowerShell `$PROFILE` 注入、winget/scoop/choco、跨平台锁与原子写
- **交叉编译与发布**：release 矩阵（darwin/linux/windows × amd64/arm64）
  + `checksums.txt` + build provenance attestation
- **`bootstrap.sh`**：`curl | bash` 薄引导（探测 OS/架构 → 下载二进制）
- **`docs/ROLLBACK.md`**：迁移期回滚指南

### 变更

- “零运行时依赖”重定义为“终端用户零运行时依赖”，**允许编译期依赖**
- 版本单一来源：`internal/version/version.go` 为唯一来源，release 由 ldflags 注入；已删除 `VERSION` 文件与 Bash 常量
- 新增模块“平台能力”语义；`shell` 在 Windows 走 PowerShell profile 分支
- **跨平台适配**（见 `docs/spec/07-cross-platform.md`）：Vim 路径（Windows `_vimrc`/`vimfiles`）、
  包 ID 映射（winget `GitHub.cli` 等）、`doctor` 按平台生成检查项、JSON 路径统一 `/` 分隔
- **`completion` 命令**：生成并注入 bash/zsh/PowerShell 补全（含 PowerShell）；安装时自动配置
- **`update` 自升级**：下载平台归档 → SHA256 校验 → 替换二进制（Windows 先改名再换入）→ 重跑 `install`
- **JSON 错误信封**：`--json` 失败统一输出 `{"ok":false,"command","data":null,"error":{"code","message"}}`
- **`gh` 官方源回退**：Debian/Ubuntu 与 RHEL 系默认源缺少 gh 时，自动添加 GitHub 官方 apt/dnf 源（Go 与 Bash 对齐）
- **`install` 交互增强（Go）**：tty 下未检测到 Git 身份时最多询问 2 个问题；非 tty/`--yes`/`--json` 自动跳过
- **细粒度子组件选择（Go 起，DESIGN §13）**：AI 模块正式名缩写为 `ai`（`ai-tools` 为兼容别名）；  `ew install ai`（整套）/ `ai/claude`（单个）/ `ai/claude ai/codex`（空格分隔多个）/ `claude codex`（简写）；
  `[ai] tools = "claude codex"` 设默认子集；`list` 暴露子组件；manifest 记录 `selected=`/`tools=`。
  枚举以空格分隔（不再用逗号）；名字含空格/特殊字符用引号。Bash 已冻结不追赶，conformance 以 `$EW_ENGINE` 守卫（G1）
- **可选 CLI 工具（Go 起，DESIGN §11/§13.6）**：`mole`（macOS/Windows）、`herdr`（全平台）、
  `glow`（全平台）、`ghostty`（终端模拟器，macOS/Linux）；**不装 GUI 应用，终端模拟器除外**。
  实现 `Optional()` 的模块**默认不在 `ew install`（无参数）安装**，仅显式 `ew install <tool>` 安装；
  且平台无支持版本时自动跳过。`list` 以 `optional:true` / 「（可选，默认不装）」标注；
  conformance 新增 G2（Go-only）
- **`vim` 模块对等**：自动安装 Node.js/ripgrep、vim-plug、18 个插件并运行 `:PlugInstall`

### 修复

- `cfg_get` 未反转义 `cfg_set` 写入的 `\"`/`\\`（引号/反斜杠值被截断）
- `remove_managed_section` 在 managed section 为文件全部内容时临时文件缺失，导致移除失败
- manifest 解析不容忍 CRLF
- `cfg_set` 顶层键（无点号）会写入空的 `[]` 节
- `bootstrap.sh`：Windows 上安装为 `ew.exe`/`easywork.exe`（此前无扩展名，Windows 无法解析）
- `bootstrap.sh`：EXIT trap 引用 `main` 的局部变量 `tmp` 导致 `set -u` 报错
- `bootstrap.sh`：支持显式 `http://` 镜像源（默认仍强制 HTTPS）
- `bin/easywork update`：`set -e` 与 `grep` 叠加导致 `--offline` 提前退出（应为 `EXIT_NETWORK=3`）

## [0.1.0] - 2026-10-08

v2 改造：从「交互式安装向导」升级为「**声明式配置 + 幂等执行引擎 + 人机/AI 双受众**」。

### 新增

- **命令 `ew`**：短命令（`easywork` 保留为软链别名），shell 补全同时覆盖两者
- **`init` 命令**：零交互轻量初始化（Shell 别名 + Git 别名，零重依赖）
- **`status` / `doctor` / `list` 命令**：状态总览、环境诊断、组件列表
- **`--json` 输出**：`version`/`status`/`list`/`doctor` 统一信封，含结构化 `update` 字段
- **`--offline`**：禁止联网（跳过下载/安装）
- **`config.toml`**：声明式配置；`config get/set`；旧 ini 自动迁移
- **`gh` 模块**：自动安装 GitHub CLI；旧发行版（apt/dnf/yum 默认源缺失）自动添加官方源
- **`ai-tools` 模块**：自动安装 claude code / codex / pi（经 npm；可经配置关闭）
- **升级提示**：安装 / 状态时提示新版本（非阻塞、24h 节流、`--offline`/`--json` 自动跳过）

### 变更

- 新增**模块引擎**（`apply_managed_file` 等），模块声明化，消除重复样板
- Shell 模块**分层**：花哨提示符 / Oh My Zsh / 网络工具默认关闭
- Git 身份**自动探测**，缺失时仍安装别名、不阻塞
- `manifest` 增加 `schema_version`；统一状态根 `EASYWORK_HOME`（可覆盖）
- 卸载时可还原用户原配置备份

### 修复

- 从交互式终端运行测试阻塞（`cmd_update` 的 `read` 等待 tty）
- 框架覆盖模块写入的 manifest 键（导致卸载无法还原备份）
- 测试隔离 `EASYWORK_*` 环境变量泄漏导致的误报

### 文档

- 新增 `AGENTS.md`（AI 协作指引）、`DESIGN.md`（v2 蓝图）
- README 增补 `--json` 示例、模块说明、跨平台支持

## [0.0.1] - 2026-06-13

首个公开版本。

- `shell` / `git` / `vim` 三个模块
- 模块自动发现、幂等 managed section、备份/还原、manifest 状态追踪
- `curl | bash` 一键安装、`install` / `uninstall` / `config` / `version` / `update` / `completion`
