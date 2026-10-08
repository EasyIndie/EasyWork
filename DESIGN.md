# EasyWork v2 设计草案

> 状态：**草案（未实施）**
> 目的：在进入「AI 时代 · 人 + AI 双受众」改造前，冻结五个中间契约，
> 使后续各子功能（声明式配置、JSON 输出、模块声明化、新模块、安全强化）
> 能够并行开发而不互相干扰。
>
> 本文档只定义**接口与契约**，不规定实现细节。实现时如发现契约需要调整，
> 先改本文档，再改代码。

---

## 1. 背景与目标

### 1.1 现状

EasyWork 是一套纯 Bash 的开发环境配置 CLI，核心能力：

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
  - 一键安装：`curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bin/ew | bash`
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

### 2.1 目录布局

```
EASYWORK_HOME（默认 ~/.easywork，环境变量可覆盖）
├── config.toml       # 声明式配置（新，见契约二）
├── config            # 旧 ini（只读兼容，迁移后废弃）
├── manifest          # 安装状态（见契约三）
├── lib/v<version>/   # 管道模式下的库缓存
└── completions/      # shell 补全文件
```

### 2.2 路径派生函数（在 common.sh 统一提供）

```bash
ew_home()         # echo "$EASYWORK_HOME"
ew_config_path()  # "$EASYWORK_HOME/config.toml"
ew_legacy_config()# "$EASYWORK_HOME/config"          （迁移用）
ew_manifest_path()# "$EASYWORK_HOME/manifest"
ew_lib_cache()    # "$EASYWORK_HOME/lib/v$EASYWORK_VERSION"
ew_completions_dir() # "$EASYWORK_HOME/completions"
```

### 2.3 规则

- `EASYWORK_HOME` 默认 `"${HOME}/.easywork"`，可通过环境变量 `EASYWORK_HOME` 覆盖（沙箱隔离用）。
- **工具状态**（config/manifest/lib/completions）一律位于 `EASYWORK_HOME` 下。
- **模块目标文件**（`~/.gitconfig`、`~/.vimrc`、`~/.sh_config_custom`）仍位于 `HOME` 下，
  通过覆盖 `HOME` 实现隔离（与现有测试做法一致）。
- 现有硬编码 `$HOME/.easywork/completions` 等位置全部改为上述函数。

---

## 3. 契约二：声明式配置 `config.toml`

### 3.1 Schema（v1，仅标量，无数组/内联表）

```toml
# ~/.easywork/config.toml
schema_version = 1

[shell]
enable_aliases      = true    # 安全别名 + g=git + q=exit（默认开）
enable_fancy_prompt = false   # 花哨提示符（含 Git 分支），默认关
enable_ohmyzsh      = false   # Oh My Zsh，默认关
enable_net_tools    = false   # macOS 网络/VPN 工具函数，默认关

[git]
identity = "personal"        # personal | work | custom
scope    = "global"          # global | local

[git.identities.personal]
name  = "张三"
email = "zhangsan@example.com"

[git.identities.work]
name  = "San Zhang"
email = "san.zhang@company.com"

[vim]
enabled = true
```

### 3.2 约束

- **仅支持标量值**：`string` / `bool` / `integer`。v1 不支持数组与内联表，
  以保证内联的简易解析器足够简单。
- 节名允许点号嵌套（`[git.identities.personal]`）；解析器在内部把「节.键」拍平为
  `git.identities.personal.name` 这种全路径键。
- 键名规范：`^[a-zA-Z_][a-zA-Z0-9_.-]*$`。
- 布尔字面量：`true` / `false`（小写）。
- 字符串可裸写或双引号包裹；`#` 为注释。

### 3.3 访问器（common.sh 提供）

```bash
cfg_get <key> [default]       # 读标量，缺失时返回 default
cfg_get_bool <key> [default]  # 返回 true/false
cfg_set <key> <value>         # 写回 config.toml（保留注释与顺序，幂等 upsert）
cfg_valid()                   # 校验语法与 schema_version
```

### 3.4 旧 ini 迁移

- 首次运行 `apply` 时若发现旧 `config`（ini）而 `config.toml` 不存在，自动迁移：
  - `GIT_PERSONAL_NAME/EMAIL` → `[git.identities.personal]`
  - `GIT_WORK_NAME/EMAIL` → `[git.identities.work]`
- 迁移后保留旧 `config` 为只读，不删除（防误删用户数据）。
- `ew config` 的查看/编辑目标改为 `config.toml`；`config edit` 打开新文件。

---

## 4. 契约三：manifest 字段

### 4.1 格式

保持现有 ini 风格，**向后兼容**，仅做字段规范化：

```
# EasyWork Manifest — auto-generated, do not edit
schema_version=1
easywork_version=0.0.1
install_date=2026-06-12T10:15:30+0800

[shell]
installed=true
shell_type=zsh
display_name=shell (zsh)
source_file=/Users/x/.zshrc
config_created=/Users/x/.sh_config_custom

[git]
installed=true
scope=global
config_file=/Users/x/.gitconfig
config_backup=/Users/x/.gitconfig.bak.20260612T101530
```

### 4.2 规范

- 顶层保留：`schema_version`、`easywork_version`、`install_date`（ISO8601 带 `%z`）。
- 每个模块节**必须**含 `installed`，取值：
  - `true` —— 已安装
  - `false` —— 未安装（可选，一般不写节）
  - `failed` —— 上次安装失败
- `failed` 时必须伴随 `failed_at`（ISO8601）；可选 `last_error`（单行）。
- `display_name` 可选，供人类友好展示。
- 模块专属键（`scope`/`config_file`/`vimrc_backup`…）为自由字段，由各模块自定，
  但键名不得与保留键（`installed`/`failed_at`/`last_error`/`display_name`）冲突。
- 状态查询命令（`status`）**只依赖** `installed` + `display_name` + `failed_at`，
  不得依赖模块专属字段。

### 4.3 访问器

现有 `manifest_*` 函数继续沿用，新增：

```bash
manifest_module_state <name>   # echo true|false|failed|absent
manifest_module_failed_at <name>
```

---

## 5. 契约四：CLI 命令与 JSON 输出

### 5.1 命令清单（v2）

| 命令 | 说明 | 是否支持 `--json` |
|---|---|---|
| `init` | 轻量默认：shell 保守别名 + git 别名，零交互、零重依赖 | 是 |
| `apply [module]` | 按 config.toml 幂等应用（**无交互**） | 是 |
| `install [module]` | 交互向导：init 基础上询问加装重组件；`--yes` ≈ init | 是 |
| `uninstall [module]` | 卸载（保留/删除配置遵循 flag） | 是 |
| `list` | 列出模块与描述 | 是 |
| `status` | 统一状态（config + 各模块） | 是 |
| `doctor` | 环境诊断（依赖/网络/权限/shell） | 是 |
| `config [show\|edit\|get K\|set K V]` | 配置文件管理 | 是 |
| `completion [setup\|remove\|status]` | 补全管理 | 否 |
| `version` | 仅输出版本号（组件状态归 `status`） | 是 |
| `update` | 升级 | 否（`--json` 留待 v2.x） |
| `help` | 帮助 | 否 |

- **无参数**：显示 `status` 摘要 + 「下一步」建议（不再显示 help）。
- **移除模块快捷命令**：`ew git` 不再等价 `ew install git`；模块名只出现在
  `list`/`status` 中，安装统一走 `ew install <模块>`。

### 5.2 全局 flag

```
--json          机器可读输出（stdout 为纯 JSON，日志走 stderr）
--dry-run       预览变更不执行
--yes, -y       跳过确认
--verbose, -v   详细输出
--offline       禁止联网（下载/update/依赖安装一律跳过并告警）
--keep-config   卸载时保留配置
--remove-config 卸载时删除配置
```

### 5.3 JSON 输出规范

- 统一信封：

```json
{ "ok": true, "command": "status", "data": { }, "error": null }
```

- `ok=false` 时 `error` 为 `{ "code": 1, "message": "..." }`（code 复用现有退出码）。
- `--json` 或 stdout 非 tty 时，stdout 禁止输出 ANSI 与日志；日志一律 stderr。
- 退出码沿用现有定义：`0` 成功 / `1` 错误 / `2` 缺依赖 / `3` 网络 / `4` 权限 / `5` 锁 / `130` 中断。

### 5.4 各命令 data 形状

```jsonc
// version
{ "version": "0.0.1", "channel": "dev",
  "install_date": "2026-06-12T10:15:30+0800",
  "installed": ["shell", "git", "vim"] }

// list
{ "modules": [
    { "name": "shell", "description": "配置 Shell 环境", "priority": 10 },
    { "name": "git",   "description": "配置 Git 别名和身份", "priority": 20 }
] }

// status
{ "config": { "path": "/Users/x/.easywork/config.toml", "valid": true },
  "modules": [
    { "name": "git", "state": "true", "ok": true, "scope": "global",
      "identity": "personal" }
  ] }

// doctor
{ "checks": [
    { "name": "curl", "ok": true,  "detail": "/usr/bin/curl" },
    { "name": "git",  "ok": true,  "detail": "2.40.0" },
    { "name": "network.github.com", "ok": false, "detail": "timeout" }
  ],
  "summary": "2/3 checks failed" }
```

> `status` 中模块的 `ok` 由「`installed=true` 且 `module_check` 通过」决定；
> `module_check` 缺失时以 manifest 为准。这正是现有半成品 `module_check`/`module_status`
> 的正式接入口。

---

## 6. 契约五：模块接口（声明式）

### 6.1 源级契约（保持不变）

每个 `lib/*.sh` 模块仍必须声明：

```bash
MODULE_NAME="git"
MODULE_DESCRIPTION="配置 Git 别名和身份"
MODULE_PRIORITY=20
```

并实现 `module_install` / `module_uninstall`。`module_check` / `module_status` / `module_doctor` 可选。

### 6.2 引擎新增函数（common.sh 统一提供，消除样板）

```bash
# 幂等写入：自动备份（记录到 backup_var）、写入 managed section
# 用法: apply_managed_file <目标文件> <内容> <注释风格> <backup_var>
#   <注释风格>: "#" 或 '"'
#   <backup_var>: 全局变量名，用于记录备份路径（无备份则为空）
apply_managed_file() { ... }

# 幂等移除：移除 managed section；若 backup_var 有值则恢复备份
# 用法: remove_managed_file <目标文件> <backup_var>
remove_managed_file() { ... }

# 声明式批量应用：遍历 MODULE_DECLARE，逐条 apply_managed_file
apply_module_files() { ... }

# 声明式批量卸载：遍历 MODULE_DECLARE，逐条 remove_managed_file
remove_module_files() { ... }
```

### 6.3 声明式模块推荐形态

```bash
MODULE_NAME="git"
MODULE_DESCRIPTION="配置 Git 别名和身份"
MODULE_PRIORITY=20

# 每条: 目标文件|内容生成函数|注释风格|备份变量名
MODULE_DECLARE=(
    "$HOME/.gitconfig|_generate_git_config|#|config_backup"
)

module_install() {
    # 1. 从 config.toml 读配置（cfg_get），无交互
    # 2. 生成内容并写入
    if ! apply_module_files; then
        return "$EXIT_ERROR"
    fi
    # 3. 记录状态
    manifest_set_section "git" \
        "installed=true" \
        "scope=$(cfg_get git.scope global)" \
        "display_name=git ($(cfg_get git.identity personal))"
    return 0
}

module_uninstall() {
    remove_module_files
    return 0
}
```

### 6.4 约束

- 模块只通过 `cfg_get`/`cfg_get_bool` 读配置，**不得**在 `module_install` 内出现
  `read -r -p` 交互（交互一律由 `install` 前端在调用前完成并写回 config.toml）。
- 所有目标文件写入必须经 `apply_managed_file`，禁止手写 managed section 逻辑。
- 需要联网/装依赖的模块，必须尊重 `--offline`（`OFFLINE=true` 时跳过并返回
  `EXIT_SUCCESS` 或明确 `EXIT_NETWORK`，由模块决定并在文档说明）。

---

## 7. 兼容与迁移

| 项 | 策略 |
|---|---|
| 旧 `config`（ini） | 首次 `apply` 自动迁移到 `config.toml`，旧文件保留只读 |
| `manifest` | 格式不变，仅新增 `schema_version` 与规范化 `installed` 取值 |
| 现有三个模块 | 逐步迁移到声明式，`module_install`/`module_uninstall` 签名不变 |
| 命令名 | `easywork` → `ew`，`easywork` 保留为软链别名 |
| 管道安装 `curl \| bash` | 安装路径不变；库文件 URL 仍按 `EASYWORK_RAW_URL` 拉取 |
| 现有测试 | `mocks.bash` 的路径覆盖改为基于 `EASYWORK_HOME` 的函数，减少逐个 export |

---

## 8. 实施批次（依赖顺序即并行边界）

```
Batch 0  【本文档】冻结契约
   │
Batch 1  契约层落地（改 common.sh + bin/easywork，一次性收口热点）
   │      · EASYWORK_HOME 统一 + 路径派生函数
   │      · config.toml 解析器 + cfg_* 访问器 + 旧 ini 迁移
   │      · --json 框架 + 信封 + 退出码统一
   │      · manifest schema_version
   │
Batch 2  模块引擎（改 common.sh）
   │      · apply_managed_file / remove_managed_file
   │      · apply_module_files / remove_module_files
   │
Batch 3  并行开发（契约已冻结，互不干扰）
   │      · 实现 doctor / status / list（契约四）
   │      · 新可选模块 modern-shell / ai-tools / editor（契约五）
   │      · 安全强化：签名校验、--offline（独立链路）
   │      · 文档：AGENTS.md、JSON Schema、README 双受众
   │
Batch 4  收口（改 shell.sh / git.sh / vim.sh，交集最大，集中一批）
          · 三个现有模块迁移到声明式
          · git 模块去交互（改读 config.toml）
          · 测试重写 mocks 路径层 + 补 JSON/非交互用例
```

**并行规则**：Batch 2 之后，Batch 3 内各子项可并行；Batch 4 因共享三个模块文件，
单独成批，不与 Batch 3 同时进行。

---

## 9. 明确不做的事（v2 边界）

- 不引入运行时依赖；config.toml 解析器必须内联/自写，禁止引入 yq/jq 等
- 不做通用 dotfiles 管理器（chezmoi/Nix 定位不重叠）
- 不做在线「模块市场」（信任与安全复杂度超出 v2 范围）
- 不丢弃 tty 下的交互、彩色输出、shell 补全
- 不一次性重写全部代码；按上述批次增量落地

---

## 10. 实施状态（截至本轮）

| 契约 / 批次 | 状态 | 落地位置 |
|---|---|---|
| 契约一 `EASYWORK_HOME` | ✅ | `lib/common.sh` 的 `ew_*` 路径函数 |
| 契约二 config.toml | ✅（主配置） | `cfg_get` / `cfg_get_bool` / `cfg_set` / `cfg_valid` / `config_migrate`；`ew config get/set` |
| 契约三 manifest | ✅ | `schema_version` + `manifest_module_state` |
| 契约四 CLI / JSON | ✅ | `--json` 信封、`json_escape`、`version`/`list`/`status`/`doctor` |
| 契约五 模块引擎 | ✅ | `apply_managed_file` / `remove_managed_file` / `apply_module_files` / `remove_module_files` |
| Batch 1 契约层 | ✅ | 见上 |
| Batch 2 模块引擎 | ✅ | 见上；shell / git / vim 已迁移 |
| Batch 3 status / doctor / `--offline` | ✅ | `cmd_status` / `cmd_doctor`；`safe_download` 离线守卫 |
| Batch 3 新模块 | ⏳ 可选 | 模块契约已支持，未内置（modern-shell / ai-tools / editor） |
| Batch 4 三模块声明化 | ✅ | git / vim 用 `MODULE_DECLARE` + 引擎 |
| 命令名 `ew` | ✅ | 安装软链 + 补全双覆盖（`ew` / `easywork`） |
| 人机体验三原则 | ✅ | `ew init` 零交互；Git 身份自动探测；shell 分层默认保守 |

**已完成 / 剩余**：

- ✅ config.toml 已成为主配置；旧 `config`（ini）仅作只读回退，首次 `install` / `config edit` 自动迁移。
- ⏳ 交互式 `install` 仍保留 Git 作用域/身份菜单（人类可选项）；零交互路径是 `ew init`。
- ⏳ 新可选模块见 §11（已定稿）。

---

## 11. 可选模块（v2.x 定稿）

> 定位：**CLI 工具，只保留核心**。不引入 GUI，不做通用现代 CLI 增强。

### 保留并新增

| 模块 | 作用 | 安装方式 |
|---|---|---|
| `gh` | 安装 GitHub CLI | brew / apt / dnf / yum / pacman / zypper / apk；apt/dnf/yum 默认源缺失时**自动添加 GitHub 官方源**；其余失败给指引 |
| `ai-tools` | 自动安装 **pi / codex / claude code** | 经 **npm**（三个都有 npm 包）；缺 npm 时给官方指引 |

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
