# EasyWork v2 设计草案

> **历史文档**：本文记录 v2 设计与 Go 迁移决策。**Bash 引擎已于 0.4.0 退役**
> （见 §15 与 `docs/RETIREMENT.md`），现行行为以 `docs/spec/` 为准。
>
> 状态：**契约已冻结并落地；Go 迁移完成、Bash 已移除（见 §12 / §15）**
> 目的：在进入「AI 时代 · 人 + AI 双受众」改造前，冻结五个中间契约，
> 使后续各子功能（声明式配置、JSON 输出、模块声明化、新模块、安全强化）
> 能够并行开发而不互相干扰。
>
> 本文档定义**设计蓝图与决策**；五个契约的**规范性接口规格**见
> [`docs/spec/`](docs/spec/README.md)。发生冲突时以 `docs/spec/` 为准；
> 修改契约须先改规格，再改实现。

---

## 1. 背景与目标

### 1.1 现状

EasyWork 是一套开发环境配置 CLI（v2 起为 Go 静态单二进制；本节描述 v2 改造前的 Bash 形态），核心能力：

- `curl | bash` 一键安装，模块自动发现（`MODULE_NAME`/`DESCRIPTION`/`PRIORITY` + `module_install`/`module_uninstall`）
- 幂等 managed section、manifest 状态追踪、备份/还原
- 三个模块：shell / git / vim

### 1.2 问题

- 交互式问答向导是「给人设计」的心智模型，AI agent 无头运行时无法消费
- 配置分散在 ini + 多个目标文件（`~/.gitconfig`、`~/.vimrc`），AI 难以生成和审查
- 模块样板代码重复（备份/写入/卸载还原逻辑在每个模块各写一遍）
- 无机器可读输出（`--json`）、无统一状态/诊断命令
- `EASYWORK_HOME` 已定义但未统一使用（`completions.sh` 仍硬编码 `~/.easywork`）
- `module_check`/`module_status` 已定义但 CLI 从未调用，状态查询是半成品

### 1.3 设计原则

1. **声明式优先**：一个配置文件描述目标环境，`apply` 幂等达成，交互只是生成配置的前端
2. **非交互是默认，交互是增强**：无 tty 时零问题跑完
3. **机器可读**：查询类命令支持 `--json`，日志与数据分离
4. **单一状态根**：一切工具状态收敛到 `EASYWORK_HOME`，可覆盖、可隔离
5. **引擎与模块分离**：核心只做「写入/备份/幂等/追踪」，模块只声明「写什么」
6. **克制**：保持零运行时依赖、单文件可分发、bash 3.2 兼容

### 1.4 命令名简化（`ew`）

- 主命令名从 `easywork`（8 字符）简化为 **`ew`**（2 字符），简短、无常见命令冲突。
- `easywork` 作为兼容别名（symlink）保留，两者完全等价；项目名仍为 **EasyWork**。
- 影响面：
  - 仓库可执行文件更名为 `bin/ew`，安装时同时创建 `easywork` 软链
  - 一键安装：`curl -sL .../bootstrap.sh | bash`（Bash 引擎退役前的管道入口为 `bin/ew`）
  - shell 补全同时覆盖 `ew` 与 `easywork`
  - 自更新路径同时识别 `ew` / `easywork`
  - 内部标识不变：`EASYWORK_*` 环境变量、`MODULE_*`、`EASYWORK_HOME`、仓库名
- 全文示例统一写 `ew`；`easywork` 仅表示别名或项目名。

### 1.5 默认值与交互策略（人机体验三原则）

1. **重活后置**：`ew init` 是默认推荐 —— shell 保守别名 + git 别名，零交互、零重依赖；
   `ew install` 是交互向导，在 init 基础上询问是否加装 vim 等重组件（`--yes` 时退化为 init）。
   Oh My Zsh、花哨提示符、网络工具全部 opt-in（config.toml 开关）。
2. **全程 ≤2 问**：交互前置合并到执行前，执行期静默；`--yes` 时全默认。
3. **身份零配置可用**：git 身份按「config.toml → git config --global 已有 → 跳过」
   探测，缺失时**不阻塞**，收尾提示补配置命令。

---

## 2. 契约一：状态根 `EASYWORK_HOME`

工具状态（`config.toml` / `manifest` / `completions/` / `run/`）只落在 `$EASYWORK_HOME`
（默认 `~/.easywork`），沙箱测试只需覆盖 `HOME` 与 `EASYWORK_HOME` 两个变量；
模块目标文件（`~/.gitconfig`、`~/.vimrc`、`.sh_config_custom` / `$PROFILE`）仍在 `HOME` 下。

实现见 `internal/platform/env.go`；规格见 [01-home.md](docs/spec/01-home.md)。

---

## 3. 契约二：声明式配置 `config.toml`

交互只是生成配置的前端，最终状态由单一文件描述。**只支持标量**（string / bool / integer）：
解析器要能在零依赖环境下实现，数组与内联表会把复杂度推给每个实现（多值用空格分隔的字符串）。

```toml
schema_version = 1

[shell]
enable_aliases = true

[git.identities.personal]
name  = "张三"
email = "zhangsan@example.com"
```

访问器语义（`Get` / `GetBool` / `Set` / `Valid` / `Has` / `Ensure` / `Migrate`）、
写入时的原子性与「保留注释与顺序」规则见 [02-config-toml.md](docs/spec/02-config-toml.md)。

---

## 4. 契约三：`manifest`（安装状态）

`$EASYWORK_HOME/manifest` 用 ini 风格记录模块状态，取值封闭为
`true` / `false` / `failed`（附 `failed_at`），并带 `schema_version` 与安装时间。
只增字段、不改变已有键，保证升降级双向可读。规格见
[03-manifest.md](docs/spec/03-manifest.md)。

---

## 5. 契约四：CLI 与 JSON 输出

命令面与参数见 [README](README.md#命令)，此处只固定不变量：

- **信封固定**：`{ "ok", "command", "data", "error" }`；失败时 `error = {code, message}`。
- **分流**：数据走 stdout，日志与进度走 stderr；`--json` 时 stdout 只有信封。
- **退出码封闭**：`0` 成功 / `1` 通用错误 / `2` 缺依赖 / `3` 网络 / `4` 权限 / `5` 锁 / `130` 中断。
- **无参数**执行 `ew` 等价 `ew status`；模块名只能用于 `install` / `uninstall`，
  不再提供「`ew git` 即安装」这类快捷命令。

字节级格式与各命令的 `data` 形状见 [04-cli-json.md](docs/spec/04-cli-json.md)。

---

## 6. 契约五：模块接口

模块**只声明**，写盘由引擎统一负责：`Name/Description/Priority/Platforms` +
`Install/Uninstall`，可选 `Optional()`（默认不装）、`Components()`（子组件）、`Aliases()`。
这样备份、还原、幂等、失败记录只在一处实现，模块之间不会互相覆盖。

- 注册顺序 = `internal/modules/module.go` 的 `registry` 顺序 = `list` 输出顺序。
- 目标文件写入只能经 `engine.ApplyManagedSection`；整体文件（plist / systemd unit）
  用 `engine.ApplyOwnedFile`（首次备份、卸载还原）。
- 规格见 [05-module-interface.md](docs/spec/05-module-interface.md)；
  managed section 的文件协议（标记、幂等、备份还原）见
  [06-managed-section.md](docs/spec/06-managed-section.md)。

---

## 7. 兼容与迁移

| 项 | 策略 |
|---|---|
| 旧 `config`（ini） | 首次 `install` / `config edit` 自动迁移到 `config.toml`，旧文件保留只读 |
| `manifest` | 只增字段；`installed` 取值封闭 |
| 模块目标文件 | managed section 标记逐字节不变，卸载可还原备份 |
| 命令名 | `easywork` 保留为 `ew` 的软链别名 |
| 状态根 | `EASYWORK_HOME` 路径与内容格式自 0.1.0 起未变 |

升级与回滚不需要数据迁移脚本，详见 [ROLLBACK.md](docs/ROLLBACK.md)。

---

## 8. 实施批次（已完成，历史记录）

v2 改造按「契约层 → 模块引擎 → 并行开发（可选模块/安全/文档）→ 三模块声明化」
四个批次推进；Bash 时代的文件（`bin/easywork`、`lib/*.sh`）已在 0.4.0 删除，
对应能力现分布在 `internal/{engine,modules,platform}`。批次划分仅作历史参考。

---

## 9. 明确不做的事（v2 边界）

- 不引入运行时依赖；config.toml 解析器必须内联/自写，禁止引入 yq/jq 等
- 不做通用 dotfiles 管理器（chezmoi/Nix 定位不重叠）
- 不做在线「模块市场」（信任与安全复杂度超出 v2 范围）
- 不丢弃 tty 下的交互、彩色输出、shell 补全
- 不一次性重写全部代码；按上述批次增量落地

---

## 10. 实施状态

五个契约均已落地并由 `tests/conformance/`（71 用例）守护；实现位置：

| 契约 | 落地位置 |
|---|---|
| 一 `EASYWORK_HOME` | `internal/platform/env.go` |
| 二 `config.toml` | `internal/engine/config.go`（`Get`/`GetBool`/`Set`/`Valid`/`Has`/`Ensure`/`Migrate`） |
| 三 `manifest` | `internal/engine/manifest.go` |
| 四 CLI / JSON | `internal/cli/*`、`internal/engine/json.go` |
| 五 模块引擎 | `internal/engine/managed.go`、`internal/engine/owned.go`、`internal/modules/*` |
| 六 managed section 协议 | `internal/engine/managed.go` |
| 七 跨平台行为 | `internal/platform/*` |
| 八 设备防休眠 | `internal/keepawake/*`（见 `docs/spec/08-keepawake.md`） |

---

## 11. 可选模块（v2.x 定稿）

> 定位：**开发工具，只保留核心**。不引入 GUI 应用（**终端模拟器除外**），不做通用现代 CLI 增强。

### 保留并新增

| 模块 | 作用 | 安装方式 | 平台 |
|---|---|---|---|
| `gh` | 安装 GitHub CLI | brew / apt / dnf / yum / pacman / zypper / apk；apt/dnf/yum 默认源缺失时**自动添加 GitHub 官方源**；其余失败给指引 | 全平台 |
| `ai`（别名 `ai-tools`） | 自动安装 **pi / codex / claude code** | 经 **npm**（三个都有 npm 包）；缺 npm 时给官方指引；支持子组件细选（§13） | 全平台 |
| `mole`（可选） | macOS 清理与优化（命令 `mo`） | brew（macOS）；Windows 官方 CLI 脚本 | macOS / Windows |
| `herdr`（可选） | Agent 运行时 | brew / 官方 `install.sh` / Windows `install.ps1` | 全平台 |
| `glow`（可选） | 终端 Markdown 渲染 | brew / apt / dnf / pacman / apk / winget / scoop / choco | 全平台 |
| `ghostty`（可选） | 终端模拟器（GUI） | macOS brew `--cask`；Linux 发行版包管理器；否则给指引 | macOS / Linux |

> **可选模块（OptionalModule）**：默认不在 `ew install`（无参数）中安装，只有显式
> `ew install <模块>` 才安装；且 `Platforms()` 未覆盖当前平台时由编排层跳过
> （“仅平台有支持版本时安装”）。**不安装 GUI 应用；终端模拟器除外（允许）。**
> 详见 §13 与 `docs/spec/05`。

### 明确不做（需要时再单独加）

- `editor`（VS Code / Cursor，**GUI**，与本工具 CLI 定位不符）
- `modern-shell`（mise / starship / zoxide / eza / bat / fd / ripgrep / delta / atuin / direnv … 全部增强）
- AI 会话编排器（vibe-kanban / claude-squad / agent-deck …）
- AI 配置管理器（bridle / agman / coder-config …）

### 安装行为约定

- 尊重 `--dry-run`（只预览）与 `--offline`（跳过联网安装）
- **幂等**：已安装则跳过
- 失败**不阻塞**整体安装（记录 manifest，给出手动安装指引）
- 核心仍**零运行时依赖**

---

## 12. 跨平台与二进制发布（v3 迁移契约）

> 状态：**决策定稿（M0）**
> 目的：在保持一套代码、单一维护成本的前提下，原生覆盖 Windows，
> 并以**跨平台静态二进制**发布。Bash 实现退居为迁移期的等价性判据（oracle）。

### 12.1 决策定稿

| 编号 | 决策 | 结论 |
|---|---|---|
| 11 | Windows 支持程度 | **两档**：WSL2 / Git Bash 保底（过渡期与 CI 冒烟）；**原生 PowerShell + winget 为终态**。终态随 Go 引擎达成，不额外维护第二套代码 |
| 12 | 迁移期双实现 | **接受**，但 Bash 版**冻结**（仅安全修复），仅作 conformance oracle，生命周期 **≤2 个 release**；以黑盒 conformance 作为唯一等价判据 |
| 13 | 二进制签名/公证 | 第一版仅 **sha256 checksums + GitHub Artifact Attestations**（免费）；Windows 代码签名 / macOS notarization **推迟到 1.0 之后**，触发条件：面向外部/企业分发或出现 SmartScreen / Gatekeeper 拦截反馈 |

### 12.2 目标架构

```
EasyWork（一套代码）
├── cmd/ew/                 # CLI 入口（命令路由，对齐 §5）
├── internal/platform/      # 平台抽象（Env/PkgManager/Lock/AtomicWrite/ShellProfile）
├── internal/engine/        # 核心引擎（config.toml / manifest / JSON / managed section）
├── internal/modules/       # 各模块（git/gh/vim/ai/shell[/shell-pwsh]）
└── legacy/（Bash，冻结）    # 迁移期 oracle，≤2 release 后归档
```

- **契约不变**：§2–§6 定义的 `EASYWORK_HOME` / `config.toml` / manifest / JSON 信封 / 模块接口
  即为跨语言 ABI，Go 版必须字节级兼容（stdout JSON、生成文件、退出码、managed 标记文本）。
- **“零运行时依赖”重定义**：终端用户仍**零运行时依赖**（`CGO_ENABLED=0` 静态单文件）；
  允许**编译期依赖**（Go module），此变更仅影响开发/构建，不影响用户。

### 12.3 平台抽象（`internal/platform`）

| 抽象 | Unix | Windows |
|---|---|---|
| `Env` | `HOME` / `TMPDIR` | `USERPROFILE` / `%TEMP%` |
| `PkgManager` | brew / apt / dnf / yum / pacman / zypper / apk | **winget（默认）/ scoop / choco** |
| `Lock` | flock → shlock → mkdir | `O_CREATE\|O_EXCL` 锁文件 + 陈旧检测 |
| `AtomicWrite` | temp + `rename` | temp + `rename`（覆盖语义）/ 必要时 `ReplaceFile` |
| `ShellProfile` | `~/.zshrc` / `~/.bash_profile` | PowerShell `$PROFILE`（CurrentUserCurrentHost，`Microsoft.PowerShell_profile.ps1`） |
| 路径 / EOL | `/`，LF | `filepath`，生成文件 CRLF |
| 可执行解析 | `PATH` | `exec.LookPath`（自动处理 `PATHEXT`） |

### 12.4 模块能力声明

模块须声明支持的平台集合，避免在 Windows 上执行无意义模块：

- `git` / `gh` / `vim` / `ai`（别名 `ai-tools`）：**全平台**
- `shell`：全平台。Unix 写 `~/.sh_config_custom` 并 source；Windows 直接向 PowerShell
  `$PROFILE` 注入 managed section（将原 `shell-pwsh` 方案折叠进本模块，以保持模块注册表跨平台一致）。

### 12.5 版本单一来源

- **唯一来源**：`internal/version/version.go` 的 `Version`。已删除 `VERSION` 文件与 Bash 硬编码常量；
  Bash 在本地 checkout 时从该文件读取版本。
- release 由 **构建期 ldflags 注入** tag：`-X github.com/EasyIndie/EasyWork/internal/version.Version=<tag>`。
- `release.yml` 校验 `tag == internal/version/version.go` 默认值。

### 12.6 分发

- **二进制发布**（CI 矩阵，不依赖 goreleaser）：`{darwin,linux,windows} × {amd64,arm64}`，
  产物 + `checksums.txt` + Artifact Attestations；矩阵显式且可本地复现（见 `scripts/acceptance.sh`）。
- **薄引导入口**：Unix `curl | bash bootstrap.sh`；Windows `irm bootstrap.ps1 | iex`。
  探测 OS/arch → 下载对应二进制到 PATH（含 PATH/PATHEXT 配置）→ 执行；不再下载 `lib/*.sh`。
- 平台包管理分发（可选）：Homebrew tap / winget manifest / Scoop bucket。

### 12.7 迁移结果

| 阶段 | 结果 |
|---|---|
| M0 决策 + spike | 决策定稿；Bash↔Go 字节等价；spike 已在 M2 后删除 |
| M1 规格 + conformance | `docs/spec/` 定稿，黑盒 conformance 成为唯一等价判据 |
| M2–M3 Go 引擎与模块 | `internal/{platform,engine,modules}`；git/gh/vim/ai/shell 逐模块过 conformance |
| M4 Windows 原生 | winget/scoop/choco、PowerShell `$PROFILE`、PATHEXT、跨平台锁；Windows 进 CI |
| M5 交叉编译与发布 | 6 目标矩阵 + `checksums.txt` + attestation（不依赖 goreleaser） |
| M6 分发与兼容 | `bootstrap.sh` / `bootstrap.ps1` 薄引导；旧 `EASYWORK_HOME` 无感 |
| M7 矩阵与回滚 | 三 OS CI + 6 目标交叉编译；`docs/ROLLBACK.md` |

迁移期 conformance 同时验证 Bash 与 Go；0.4.0 起 Bash 退役（§15），门禁收敛为
`tests/conformance/run.sh go`。

---

## 13. 细粒度组件选择（v2.x，Go 起）

> 解决的问题：安装粒度只有「模块」一档，无法同时满足「只装 1 个工具」与
> 「装一整套/一类子集」。`ai` 这类大类尤其需要子选择。

### 13.0 模块命名

- AI 模块正式名从 `ai-tools` **缩短为 `ai`**；`ai-tools` 保留为**兼容别名**
  （`module` 查找、manifest 节、config 节均兼容旧名）。
- Bash 引擎文件名仍为 `lib/ai-tools.sh`（已冻结，不背负缩写改动），
  Go 引擎对外暴露 `ai`；conformance 用 `$EW_ENGINE` 区分。

### 13.1 三层概念

| 层 | 例子 | 说明 |
|---|---|---|
| 模块（大类） | `ai` | 顶层安装单元，必选 |
| 子组件（选装项） | `ai/claude` | 可选声明（实现了 `Components()` 才有） |
| 简写 | `claude` | 全仓库唯一时自动解析为所属模块的子组件 |

### 13.2 命令语法（install）

枚举**以空格分隔**（即 shell 的多个参数），**不使用逗号**；名字含空格/特殊字符时
用引号作为单个参数传入：

```bash
ew install ai                 # 整套（全部子组件）
ew install ai/claude          # 仅 1 个
ew install ai/claude ai/codex # 两个（空格分隔）
ew install claude codex       # 多个简写（空格分隔）
ew install git ai/pi          # 混合：模块 + 子组件
ew install "ai/my tool"       # 名字含空格（引号）
```

解析规则：

- shell 已按空白分词；每个参数为一个目标：`module`、`module/component` 或 `component`。
- 参数**原样保留**（不 trim）；`module/component` 在**首个 `/`** 处切分；
  子组件名不得为空、不得再含 `/`、不得含控制字符（空格等可打印字符允许）。
- 逗号是**名字的一部分**，不再是分隔符。
- `module`（无子组件）= 该模块全部子组件；若同时给 `module/comp`，则「整模块」语义优先。
- 未知模块 / 未知子组件 / 无法消歧的简写 → 退出码 `1`，并给出可用项提示。
- 未在参数中出现的模块**不安装**；无参数 = 全部模块（各自全部子组件）。

### 13.3 配置默认值（config.toml）

- `[ai] tools = "claude codex"`（**空格分隔**）：无 CLI 显式子组件时的默认子集；
  留空/注释 = 全部。兼容旧 `[ai_tools] tools`。
- 优先级：**CLI 显式选择 > `ai.tools` > 全部**。
- 仍受 `ai.install = false` 总开关约束（兼容旧 `ai_tools.install`）。

### 13.4 manifest 记录

`[ai]` 节新增/保留（旧 `[ai-tools]` 节仍可读）：

```ini
[ai]
installed=true
selected=claude,codex   # 本次请求的子集（内部以 CSV 记录）
tools=claude            # 实际装成（已存在或安装成功）
```

### 13.5 通用性与边界

- 机制在**模块接口层**（`Components()` + `Context.Selected` + `Aliases()`）实现，
  任何模块都可声明子组件/别名；未声明子组件的模块行为不变。
- `list`（人类输出与 `--json`）展示子组件，便于发现可选值；shell 补全包含
  `module/component`、简写与别名。
- **仅 Go 引擎实现**：Bash 已冻结，不追赶该特性；conformance 用 `$EW_ENGINE` 守卫。
- `uninstall` 接受 `module/component` 语法但粒度为模块（卸载语义仍是移除整模块）。
- 子组件名含空格时，shell 补全与 config 空格分隔表达会受限（保留为已知边界）。

### 13.6 可选模块（默认不装）

模块可实现 `Optional() bool`（`OptionalModule`）。标记为可选时：

- `ew install`（无参数）**跳过**，避免默认装 GUI/重组件（也保护 CI/发布流水线）；
- 仅显式 `ew install <module>` 安装；
- 平台门控：`Platforms()` 未覆盖当前平台 → 编排层输出「跳过 X（当前平台不支持）」并继续。
- `list` 以 `optional:true`（JSON）与「（可选，默认不装）」标注。

可选工具（平台以“有支持版本”为准）：

| 模块 | macOS | Linux | Windows | 安装方式 |
|---|---|---|---|---|
| `mole`（`mo`） | ✅ | ❌ | ✅ | brew / 官方 Windows CLI 脚本 |
| `herdr` | ✅ | ✅ | ✅ | brew / 官方 `install.sh` / `install.ps1` |
| `glow` | ✅ | ✅ | ✅ | brew / apt / dnf / pacman / apk / winget / scoop / choco |
| `ghostty` | ✅ | ✅ | ❌ | macOS `brew --cask`；Linux 发行版包管理器 |

> 不装 GUI 应用；**终端模拟器除外**（Ghostty 为允许项）。


---

## 14. 设备防休眠 `keepawake`（v0.3，已实现；规格见 `docs/spec/08-keepawake.md`）

**动机**：`ew install`、依赖下载、远程编译、常驻服务这类长跑任务不该被睡眠打断；
但"防休眠"在笔记本上极易做错（把电池耗光、或以为合盖也能跑）。

### 14.1 决策

| 决策 | 结论 | 理由 |
|---|---|---|
| 是否改系统电源策略 | **不改**（不用 `pmset`/`powercfg`） | 需 sudo、系统升级可能被重置、笔记本语义错 |
| macOS 参数 | 默认 `caffeinate -s` | `-s` 仅在接电时被 `powerd` 采纳：拔电自动失效、复电自动恢复 |
| `-i`/`-d` 何时用 | 仅 `mode=always` / `display=true` | 笔记本上 `-i` 会持续耗电；`-m`/`-u` 无价值，不采用 |
| 默认 | `enabled=false`、`mode=ac` | 遵循「人机体验三原则」：不做惊吓式默认 |
| 模块形态 | 可选模块（`Optional()=true`），`Priority=75` | 默认 `ew install` 不装；显式指名才装 |

### 14.2 配置与命令

```toml
[keepawake]
enabled = "false"   # ew keepawake on 会写 true
mode    = "ac"      # ac | always（Linux/Windows 无 ac 等价物 → 降级并标记 mode_degraded）
display = "false"   # 连显示器一起防睡
persist = "false"   # 写开机自启（LaunchAgent / systemd 用户单元 / 计划任务）
```

- `ew keepawake on [--always|--ac] [--display] [--persist]`：写配置 + 立即生效（幂等）
- `ew keepawake off`：写 `enabled=false` + 停断言 + 拆自启（恒成功）
- `ew keepawake status [--json]`：只读探测，五态 `active|pending-ac|stale|inactive|unsupported`
- `ew apply keepawake` / `ew install keepawake`：按 config 收敛

### 14.3 跨平台后端

| 平台 | 运行态 | 自启 |
|---|---|---|
| macOS | `/usr/bin/caffeinate`（`-s`，可加 `-d`/`-i`） | `~/Library/LaunchAgents/com.easyindie.easywork.keepawake.plist` |
| Linux | `systemd-inhibit --what=sleep:idle … sleep infinity` | `~/.config/systemd/user/easywork-keepawake.service` |
| Windows | `keepawake.ps1` + `powershell -File`，每 30 s 续订 `SetThreadExecutionState` | `keepawake.cmd` 启动器 + `schtasks /SC ONLOGON` |

### 14.4 边界（帮助与 `status` 必须如实说明）

- **合盖必睡**（M1/M2 亦然；clamshell 需接电 + 外接屏）——`status` 在 `active` 时固定提示保持开盖；
- 手动睡眠、电量耗尽、过热保护均不受断言约束；
- 重启后需 `persist=true` 才恢复；`off` 会同时拆除自启，避免"关不掉"。

### 14.5 写盘原语扩展

plist / systemd unit 是整体文件，无法使用 managed section。新增
`engine.ApplyOwnedFile` / `engine.RemoveOwnedFile`（整文件接管 + 首次备份 + 卸载还原），
仅用于 EasyWork 专属路径；删除前校验文件含 EasyWork 标记，防止误删同名文件。

### 14.6 Windows 实现约束（真机踩坑，已固化进 `docs/spec/08-keepawake.md §7.1`）

- 进程创建用 `CREATE_NO_WINDOW`，**不能用 `DETACHED_PROCESS`**（PowerShell 会立即 exit 0）；
- 必须带 `CREATE_BREAKAWAY_FROM_JOB`，否则 SSH 断开时子进程被 Job 连带杀掉；
- 脚本一律落盘 `.ps1` 用 `-File` 执行（内联 `-Command` 的引号会被命令行转义破坏）；
- 存活判定用 `tasklist`（session 0 下 WMI `CommandLine` 可能为 null）；
- 生成的脚本/启动器保持纯 ASCII（PowerShell 5.1 按 ANSI 解析无 BOM 文件）；
- `mode`/`display` 变更必须重启后端，不能当作幂等；
- EasyWork 自有资产覆盖不产生 `.bak`。

---

## 15. Bash 引擎退役（0.4.0）

> 执行记录与前置条件核对见 [`docs/RETIREMENT.md`](docs/RETIREMENT.md)。

### 15.1 触发条件

- Go 引擎连续 2 个 release（0.2.0 / 0.2.1）无反回滚事故；
- conformance 在 Bash 与 Go 双实现上全绿（65×2）；
- 用户数据契约稳定：`EASYWORK_HOME` / `config.toml` / `manifest` / managed section 逐字节不变。

### 15.2 退役前补的门禁

| 门禁 | 原因 | 落点 |
|---|---|---|
| `bootstrap.sh` 端到端 | 退役后它是 Unix 唯一安装入口，此前只有 `bash -n` | `scripts/bootstrap-e2e.sh`（本地镜像：指定版本 / latest 解析 / 篡改拦截） |
| `bootstrap.ps1` 端到端 | Windows 唯一安装入口，此前只有真机手测 | `scripts/bootstrap-e2e.ps1`（同三条路径 + `irm \| iex`；CI 在 windows-latest 用 PS 5.1 与 pwsh 7 各跑一次） |
| sha256 完整性校验 | 原 `bootstrap.sh` 只下载不校验 | `verify_checksum()`；缺失 checksums 时告警跳过 |
| update 自升级进 CI | 退役后升级只剩这条链路 | `install-e2e` job（`make check` 亦覆盖） |
| 迁入 4 条 e2e 断言 | Bash 白盒测试删除后避免覆盖缺口 | C4-init / C5-single-module / C6-partial-uninstall / C6-dry-run |

### 15.3 删除清单

`bin/easywork`、`lib/*.sh`、`MODULES`、`easywork.conf.example`、
`tests/test_*.bats`（192 用例）、`tests/helpers/mocks.bash`、`tests/run.sh`。

### 15.4 守卫

`make retire-check`（`scripts/retire-check.sh`）语义反转为**不变量检查**：
断言旧文件不复活、`bootstrap.sh` 带完整性校验、conformance/release/CI/Makefile 只针对 Go。

### 15.5 影响

- 用户无迁移：同一 `EASYWORK_HOME`，`bootstrap.sh` 安装的二进制直接接管；
- 失去的能力仅"Bash 自下载库文件"的管道安装（由 `bootstrap.sh` 取代）；
- 回滚：`git checkout legacy-bash-0.3.0`。
