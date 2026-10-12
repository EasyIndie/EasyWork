# 契约五：模块接口与声明式引擎

> 规格编号：C5 ｜ 对应 DESIGN §6 ｜ 状态：冻结

## 模块描述符

一个模块是一个可发现、可注册的单元，声明以下元数据：

| 字段 | 必填 | 约束 |
|---|---|---|
| `name` | 是 | 匹配 `^[a-zA-Z0-9_-]+$`；不得为保留字 `install`/`uninstall`/`config`/`version`/`update`；不得含空白/控制字符/路径穿越（`/`、`..`） |
| `description` | 否 | 单行中文/英文描述，默认空 |
| `priority` | 否 | 整数，默认 `50`；越小越先执行 |
| `platforms` | 否 | 支持平台集合 ⊆ {`macos`,`linux`,`windows`}；默认全平台 |

### 注册顺序（不变量）

- 注册顺序 = 模块**源文件名的字母序**（Bash：`_discover_modules` 扫描 `lib/*.sh`，
  跳过 `common.sh`/`completions.sh`/`install.sh`）。
- `list` 按注册顺序输出；`status` 按 `priority` 升序（同优先级保持注册顺序）。
- 重复注册同名模块为 no-op（首个生效）。
- 非法名字 → 报错并退出 `1`。

### 平台能力

- 模块必须声明其支持平台；在不支持的平台上，`install` 应为**成功跳过**
  （不得报错、不得写盘），`status` 报告为「不支持」。
- `git`/`gh`/`vim`/`ai`（别名 `ai-tools`）：全平台。`shell`：仅 `macos`/`linux`（Windows 另设
  `shell-pwsh`，见 DESIGN §12.4）。
- 可选工具（v2.x / Go 起）：`glow`/`herdr` 全平台；`mole` 仅 `macos`/`windows`；
  `ghostty`（终端模拟器）仅 `macos`/`linux`。

## 可选模块（v2.x / Go 起）

模块可实现可选接口 `optional`（`Optional() bool`）。标记为可选时：

- `ew install`（**无参数**）**跳过**该模块（避免默认装重组件/GUI，也保护 CI 与发布流水线）；
- 仅显式 `ew install <module>` 时安装；
- 平台门控不变：`platforms` 未覆盖当前平台 → 编排层输出「跳过 X（当前平台不支持）」并继续；
- `list` 以 `"optional": true`（JSON，缺省省略）与「（可选，默认不装）」标注。
- 当前可选模块：`mole` / `herdr` / `glow` / `ghostty`（Bash 已冻结，不实现）。
- **不安装 GUI 应用；终端模拟器除外（允许）。**

## 能力接口（语言无关）

模块可实现以下操作（`install`/`uninstall` 必须存在）：

| 操作 | 签名（逻辑） | 语义 |
|---|---|---|
| `install` | `(ctx) -> exitCode` | 幂等应用配置；**禁止交互**；读 `config.toml`；写 manifest |
| `uninstall` | `(ctx) -> exitCode` | 移除本模块写入的内容，按需还原备份；可保留外部工具 |
| `check` | `(ctx) -> bool` | 是否已应用 |
| `status` | `(ctx) -> string` | 人类可读单行状态 |
| `doctor` | `(ctx) -> []check` | 可选诊断项 |

`ctx` 至少提供：`config`（`get`/`get_bool`）、`manifest`（`set_section`）、
`files`（声明式引擎）、`flags`（`dryRun`/`offline`/`yes`）、`log`、`env`、
`selected`（本模块被 CLI 显式选中的子组件名，可空）、`componentSelected(name)`。

### 约束

- `install` 内**不得**出现交互（`read -p` 等）；交互由 `install` 前端在调用前完成并写回 config。
- **所有目标文件写入必须经声明式引擎**，禁止模块手写 managed section 逻辑。
- 联网/装依赖的模块必须尊重 `--offline`（跳过并返回成功或明确的网络错误）。
- 失败**不阻塞**整体安装：编排层记录 manifest 并汇总提示。

## 子组件（可选，v2.x / Go 起）

模块可声明子组件（选装项），以支持「只装 1 个 / 装一整套 / 装子集」三种粒度（DESIGN §13）：

| 字段 | 约束 |
|---|---|
| `name` | 在所属模块内唯一；匹配 `^[a-zA-Z0-9_-]+$` |
| `description` | 单行描述，默认空 |

- 声明后该模块可被细粒度选择：`install <module>/<component>`。
- `ctx.selected` 为该模块被显式选中的子组件名（空 = 未选择 = 全部）；
  `componentSelected(name)` 在未选择时返回 `true`。
- 模块可用 config 默认值进一步收窄（如 `[ai] tools`）；优先级
  **CLI 显式选择 > config > 全部**。
- 未声明子组件的模块**行为不变**（机制在接口层，非 ai 专有）。
- `list` 的 JSON 中此类模块附加可选字段 `components`（见契约四）；
  人类输出缩进展示。
- manifest 可记录 `selected=`（请求子集）与 `tools=`（实际装成）。
- **语言归属**：Bash 实现已冻结，不实现本增量；conformance 用 `$EW_ENGINE` 守卫（G1，仅 Go）。
- 模块可声明兼容别名（如 `ai` 的别名 `ai-tools`）：`module` 查找、manifest 节与
  config 节均回退旧名。

## 声明式文件目标

模块可声明一组「目标文件」，由引擎统一执行备份/写入/还原：

```
entry := { target: path,
           content: fn(ctx) -> string,
           comment: "#" | "\"",       # managed section 标记注释风格
           backupVar: name }          # 引擎回写备份路径的槽位
```

### 引擎操作

| 操作 | 语义 |
|---|---|
| `apply_module_files(mod)` | 遍历声明：生成内容 → `ApplyManagedSection(target, content, comment)`，需要时备份并把路径写入 `backupVar` |
| `remove_module_files(mod)` | 遍历声明：`RemoveManagedSection(target)`；若 `backupVar` 有值且备份存在则还原 |

- 单个入口失败即中止该模块的批量应用并返回失败。
- 备份路径变量在模块内可读，用于写入 manifest（如 `config_backup`）。

## 安装编排（与模块的边界）

1. 解析目标模块（默认全部）；未知模块 → 报错 + 列出可用模块。
2. 逐个按 `priority` 升序执行 `install`。
3. 成功后：若模块未自写 manifest 节，编排层回退写 `installed=true`；
   模块已自写则**不覆盖**。
4. 失败：写 `installed=failed` + `failed_at`；继续下一模块；结束时汇总。

## 验收点（C5）

- `C5-register`：解析各模块的 name/description/priority；保留字/非法名报错。
- `C5-order`：`list` 注册序、`status` 优先级序。
- `C5-platform`：不支持平台上的模块跳过且不写盘。
- `C5-declare`：`apply_module_files` 写入并记录备份路径；`remove_module_files` 还原。
- `C5-no-interactive`：`install --yes` 全程无 stdin 读取。
- `C5-failure`：失败模块写 `failed` 且不阻塞后续模块。

### 验收点（G1，仅 Go 引擎）

- `G1-list-components`：`list`（人类与 `--json`）展示子组件。
- `G1-select`：`install module/component`、空格分隔多个目标、`component` 简写各自生效。
- `G1-config-default`：无 CLI 选择时 `ai.tools` 生效，CLI 选择覆盖之。
- `G1-unknown`：未知模块/子组件 → 退出码 `1`。

### 验收点（G2，仅 Go 引擎）

- `G2-optional`：可选模块默认不在 `ew install` 安装；显式指名才安装。
- `G2-platform`：不支持的平台上 `install <可选模块>` 被跳过（退出码 `0`）。
- `G2-list`：`list` 以 `optional:true` 标注可选模块。
