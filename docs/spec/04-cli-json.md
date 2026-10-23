# 契约四：CLI 命令与 JSON 输出

> 规格编号：C4 ｜ 对应 DESIGN §5 ｜ 状态：冻结

## 命令清单

| 命令 | 说明 | `--json` | 规格状态 |
|---|---|---|---|
| `status` | 统一状态（config + 各模块） | 是 | **冻结**（见下） |
| `list` | 列出模块与描述 | 是 | **冻结** |
| `version` | 版本与已装组件 | 是 | **冻结** |
| `doctor` | 环境诊断 | 是 | **冻结** |
| `init` | 轻量默认（shell+git），零交互 | 是 | 规划 |
| `install [module]` | 按 config.toml 幂等安装（`--yes` ≈ init）；重复执行即「收敛」 | 是 | 规划 |
| `uninstall [module]` | 卸载 | 是 | 规划 |
| `config [show\|edit\|get K\|set K V]` | 配置管理 | 是 | 规划 |
| `completion [setup\|remove\|status]` | 补全管理 | 否 | — |
| `update` | 检查并自升级（下载归档→校验→替换→重跑 install） | 否 | — |
| `help` | 帮助 | 否 | — |

- **无参数**：stdin 非 tty 或处于管道模式 → 等价 `install --yes`；否则 → `status`。
- 模块名不再作为快捷命令（`ew git` 报错并提示 `ew install git`）。

## 全局 flag

| flag | 语义 |
|---|---|
| `--json` | stdout 仅 JSON；日志走 stderr |
| `--dry-run` | 预览，不写盘/不执行 |
| `--yes` `-y` | 跳过确认 |
| `--verbose` `-v` | 详细日志 |
| `--offline` | 禁止联网；`update` 片段返回 `null`/`false` |
| `--keep-config` | 卸载保留配置 |
| `--remove-config` | 卸载删除配置 |

- flag 可在子命令**前或后**；解析时从参数流中移除，剩余第一个非 flag 为子命令。

## JSON 编码规则（字节级）

实现必须产生与以下完全一致的字节：

1. **紧凑格式**：无任何多余空白（`,` `:` 后无空格）。
2. **字段顺序固定**：按本规格给出的顺序，不得重排。
3. **单行 + 末尾 1 个 `\n`**。
4. **UTF-8 原样输出**：非 ASCII 字符（如中文）**不得**转义为 `\uXXXX`。
5. **字符串转义**（仅此 5 种）：`\` → `\\`，`"` → `\"`，LF → `\n`，
   CR → `\r`，TAB → `\t`。其他控制字符不应出现在值中（上游须清洗）。
6. **禁止 HTML 转义**：`<` `>` `&` 原样输出（Go 实现须 `SetEscapeHTML(false)`）。
7. 布尔为小写 `true`/`false`；空值用 `null`；整数字面量无前导零。

## 信封

成功：

```json
{"ok":true,"command":"<cmd>","data":{...},"error":null}
```

失败（已实现）：

```json
{"ok":false,"command":"<cmd>","data":null,"error":{"code":1,"message":"..."}}
```

字段顺序固定为 `ok` `command` `data` `error`；`code` 复用退出码。

- 任何命令在 `--json` 下失败（退出码非 0）时，stdout 输出上述信封，日志走 stderr。
- `command` 为触发的子命令（未知命令时为该未知词）。

## 各命令 `data` 形状（冻结）

### `status`

```json
{"config":{"path":"<abs>","exists":true,"valid":true},
 "modules":[{"name":"shell","state":"true","ok":true}],
 "update":{"latest":null,"available":false}}
```

- `config.path` = `config.toml` 绝对路径；`exists` 文件存在；`valid` 见契约二
  （文件不存在视为 `true`）。
- `modules` 按 `priority` **升序**（同优先级保持注册顺序）。
- `state` ∈ `true|false|failed|absent`（契约三）；`ok = (state=="true")`。

### `list`

```json
{"modules":[{"name":"ai","description":"...","priority":50}],
 "update":{"latest":null,"available":false}}
```

- `modules` 按**注册顺序**（实现扫描模块文件的字母序），非优先级排序。
- **v2.x（Go 起增量）**：声明了子组件的模块附加可选字段 `components`：
  `{"name":"ai","description":"...","priority":50,"components":[{"name":"claude","description":"..."}]}`。
  无子组件的模块省略该字段。模块正式名为 `ai`（历史名 `ai-tools` 作为别名保留；
  `ai-tools` 为兼容别名，见 DESIGN §13）。
- **v2.x（Go 起增量）**：可选模块附加 `"optional":true`（缺省省略）；`ew install`
  无参数时跳过可选模块（见契约五「可选模块」）。

## `install` 目标语法（v2.x，Go 起）

枚举**以空格分隔**（shell 多个参数），**不使用逗号**；含空格的名字用引号：

```bash
ew install ai                 # 模块（全部子组件）
ew install ai/claude          # 单个子组件
ew install ai/claude ai/codex # 多个目标（空格分隔）
ew install claude codex       # 多个简写
ew install git ai/pi          # 混合
ew install "ai/my tool"       # 名字含空格
```

- 未在参数中出现的模块不安装；无参数 = 全部模块。
- 未知模块 / 未知子组件 / 无法消歧的简写 → 退出码 `1`。
- 优先级：CLI 显式选择 > `[ai] tools` > 全部。

### `version`

```json
{"version":"0.1.0","channel":"dev","install_date":"",
 "installed":["shell","git"],"update":{"latest":null,"available":false}}
```

- `channel`：release 为空字符串；本地 checkout 或 main 分支管道 = `dev`。
- `install_date`：无 manifest 时 `""`；否则取 manifest 顶层值。
- `installed`：`installed=true` 的模块名数组，保持 manifest 出现顺序；无则 `[]`。

### `doctor`

```json
{"checks":[{"name":"curl","ok":true,"detail":"/usr/bin/curl"}],
 "update":{"latest":null,"available":false}}
```

- `checks` 固定顺序：`curl`、`git`、`awk`、`sed`、`zsh`、`network`。
- `detail`：命令存在时为绝对路径或版本；缺失时为 `missing`（zsh 为
  `optional (Oh My Zsh 将跳过)`）；`network` 为 `github.com reachable` /
  `github.com unreachable`。

### `update` 片段（所有查询命令共有）

```json
{"latest":"v1.0.0","available":true}
```

- `--offline` 或查询失败 → `{"latest":null,"available":false}`。
- `available` = `latest` 语义版本 > 当前版本。
- 结果缓存于 `${EASYWORK_HOME}/.last_update_check`（第 1 行 unix 秒，第 2 行版本），
  24h 内复用。

## 日志与数据分流

- `--json` 时：`log_info` / `log_success` 改写 stderr；`log_warn` / `log_error`
  始终 stderr；stdout 只有 JSON。
- 非 JSON 时日志走 stdout。
- （设计目标，非本期规范）stdout 非 tty 时自动启用 JSON。

## `install` 交互增强

- 仅在 **tty 且未 `--yes`/`--json`/`--dry-run`** 时启用；最多 **2 问**（Git 用户名、邮箱）。
- 已有身份（`config.toml` 或 `git config --global user.name`）则跳过。
- 身份缺失**不阻塞**；零交互路径为 `ew init`。

## `update` 自升级

- 解析最新 tag（GitHub API）→ 下载**对应平台归档**（`easywork_<ver>_<goos>_<arch>.tar.gz`，
  Windows 为 `.zip`）→ 校验 `checksums.txt`（存在时）→ 替换当前可执行文件 → 重跑 `install --yes`。
- `--offline`：不联网，返回 `3`（`EXIT_NETWORK`）。
- 非交互且未 `--yes`：只提示，不升级。
- 替换语义：Unix 同目录 `rename` 覆盖；Windows 运行中 exe 不可删除，先 `rename` 为 `.old`
  再换入新文件，下次启动清理 `.old`。
- 可覆盖环境变量：`EASYWORK_RELEASE_URL`（资产基址）、`EASYWORK_API_URL`（tag 来源）；
  `EASYWORK_UPDATE_SKIP_REINSTALL=true` 跳过升级后的 `install`。

## 退出码

`0` 成功 ｜ `1` 通用错误 ｜ `2` 缺依赖 ｜ `3` 网络 ｜ `4` 权限 ｜ `5` 锁 ｜ `130` 中断。

## 验收点（C4）

- `C4-status-shape` / `C4-list-shape` / `C4-version-shape` / `C4-doctor-shape`：
  stdout **字节级固定**（`--offline`；Bash 引擎退役前的等价判据已转为 golden 断言）。
- `C4-order`：status 按优先级、list 按注册顺序、doctor 检查项顺序。
- `C4-offline`：`update` 片段为 `null`/`false`。
- `C4-escape`：含 `"` `\` 与中文的值编码正确。
- `C4-log-split`：`--json` 时 stdout 不含日志、stderr 不含 JSON。
- `C4-exit`：缺依赖/未知命令等退出码。
