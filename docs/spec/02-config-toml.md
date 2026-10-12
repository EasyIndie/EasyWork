# 契约二：声明式配置 `config.toml`

> 规格编号：C2 ｜ 对应 DESIGN §3 ｜ 状态：冻结

## 目的

用单一、可被 AI 直接生成/审查的声明式文件描述目标环境；交互只是生成该配置的前端。

## 格式（TOML v1 子集）

```toml
schema_version = 1

[shell]
enable_aliases      = true
enable_fancy_prompt = false

[git]
identity = "personal"

[git.identities.personal]
name  = "张三"
email = "zhangsan@example.com"
```

### 语法约束（实现只需支持这些）

- **仅标量**：`string` / `bool` / `integer`。**不支持**数组、内联表、多行字符串、日期。
- 节名可含点号（`[git.identities.personal]`）；点号表示层级，读取时拍平为
  `git.identities.personal.name` 全路径键。
- 键名匹配 `^[a-zA-Z_][a-zA-Z0-9_.-]*$`。
- 注释以 `#` 起（行首或值后）。
- 字符串可裸写或双引号包裹。双引号内支持转义：`\"`、`\\`、`\n`、`\t`；
  未知转义原样保留（`\x` → `\x`）。
- 布尔字面量小写 `true`/`false`；整数按十进制文本处理。
- **多值选择用空格分隔的标量**（因 v1 不支持数组），例如
  `[ai] tools = "claude codex"`；空/缺省 = 全部。见 DESIGN §13。

## 读取语义

### `get(key[, default]) -> string`

1. `config.toml` 不存在 → 返回 `default`（默认 `""`）。
2. `key` 含 `.`：最后一个 `.` 之前为 `section`，之后为 `keyname`；无 `.` 则
   `section=""`（顶层）。
3. 逐行扫描，维护 `current_section`：
   - 跳过空行与 `#` 注释行；
   - `[section]` 行更新 `current_section`；
   - 仅当 `current_section == want_section` 时匹配 `keyname = ...`；
   - 左侧须**精确等于** `keyname`（`=` 两侧空白忽略）。
4. 取右侧标量：先 trim；若以 `"` 开头，按双引号字符串解析并**反转义**
   `\"` `\\` `\n` `\t`（遇到未转义的 `"` 结束）；否则截断首个 `#` 再 trim。
5. 未命中 → 返回 `default`。

### `get_bool(key[, default]) -> "true" | "false"`

先 `get`，再归一化：

| 输入（大小写不敏感） | 结果 |
|---|---|
| `true` `1` `yes` `on` | `true` |
| `false` `0` `no` `off` | `false` |
| 其他 | 返回 `default`（默认 `false`） |

### `valid() -> bool`

- 文件不存在 → `true`。
- 存在且 `schema_version == "1"` → `true`；否则 `false`。
- 失败时向 stderr 记录警告。

## 写入语义

### `set(key, value)`

- 缺失则创建文件，首行写 `schema_version = 1`。
- **值一律以双引号字符串写入**：`keyname = "value"`；转义 `\` → `\\`、`"` → `\"`。
- 若目标节存在：就地 upsert 该键，**保留其余行、注释与顺序**。
- 若目标节不存在：文件末尾追加空行 + `[section]` + `keyname = "value"`。
- 写入须“临时文件 + rename”原子完成。
- 全路径键：`a.b.c` → 节 `a.b`，键 `c`。

## 初始化与迁移

- `init` / 首次写配置时：`config.toml` 不存在则
  1. 若存在旧 `config`（ini）：迁移（见下）；
  2. 否则写入默认模板（含 `schema_version=1`、`[shell]`、`[git]`、`[ai]`）。
- **旧 ini 迁移**（`config` → `config.toml`，仅当 `config.toml` 不存在）：
  - 读取 ini 的 `GIT_PERSONAL_NAME` / `GIT_PERSONAL_EMAIL` →
    `[git.identities.personal]`
  - `GIT_WORK_NAME` / `GIT_WORK_EMAIL` → `[git.identities.work]`
  - 旧 `config` 迁移后**保留**（只读回退，不删除）。
- 读取优先级：`config.toml` > 旧 `config`。

## 验收点（C2）

- `C2-get-scalar`：顶层/节内标量、点号节、默认值。
- `C2-get-quoted`：双引号值（含 `#`）与裸值（含行尾 `#` 注释）。
- `C2-get-bool`：六种真值、六种假值、非法值回落默认。
- `C2-set-upsert`：更新已有键保留注释与顺序；新增键；新建节。
- `C2-set-quote`：含 `"` 与 `\` 的值写入后能被 `get` 还原。
- `C2-valid`：`schema_version=2` → `false`；缺文件 → `true`。
- `C2-migrate`：旧 ini 存在且无 config.toml 时迁移；旧文件保留。
