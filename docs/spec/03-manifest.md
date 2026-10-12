# 契约三：安装状态 `manifest`

> 规格编号：C3 ｜ 对应 DESIGN §4 ｜ 状态：冻结

## 位置

`${EASYWORK_HOME}/manifest`

## 格式（ini 风格，向后兼容）

```
# EasyWork Manifest — auto-generated, do not edit
schema_version=1
easywork_version=0.1.0
install_date=2026-06-12T10:15:30+0800

[shell]
installed=true
shell_type=zsh
display_name=shell (zsh)
source_file=/Users/x/.zshrc

[git]
installed=true
scope=global
config_file=/Users/x/.gitconfig
```

### 顶层键

| 键 | 必填 | 说明 |
|---|---|---|
| `schema_version` | 是 | 当前 `1` |
| `easywork_version` | 是 | 写入时的工具版本 |
| `install_date` | 是 | ISO8601，格式 `%Y-%m-%dT%H:%M:%S%z`（如 `2026-06-12T10:15:30+0800`） |

### 模块节

- 节名 = 模块名（`[git]`）。
- **保留键**：`installed`、`failed_at`、`last_error`、`display_name`。
- `installed` 取值封闭：`true` / `false` / `failed`。
  - `failed` **必须**伴随 `failed_at`（同 `install_date` 格式）；可选 `last_error`（单行）。
- 其余键为模块自由字段，不得与保留键冲突。
- `display_name` 供人类友好展示。

### 不变量

- `status` 查询**只依赖** `installed`、`display_name`、`failed_at`，不得依赖模块自由字段。
- **空行/行序不参与语义**：解析不得依赖空行或节的行位置；写入实现可在节间保留
  或去除空行。conformance 对 manifest 做空行规范化后比较，而非逐字节比较。
- manifest 解析须容忍 Windows CRLF 与旧文件（缺 `schema_version` 时默认 `1`）。

## 操作语义

| 操作 | 语义 |
|---|---|
| `exists()` | 文件存在 |
| `read(top_key[, default])` | 读取顶层键（首列 `key=` 起始，取 `=` 后全部） |
| `read_section_key(section, key[, default])` | 在 `[section]` 内精确匹配 `key=`；遇下一节 `[` 停止 |
| `module_state(name)` | 返回节内 `installed` 原值；无该节/无键 → `absent` |
| `list_installed()` | 输出所有 `installed=true` 的节名 |
| `init(version)` | 新建：头部注释 + `schema_version=1` + `easywork_version` + `install_date` |
| `set_section(name, k=v...)` | **整节替换**：删除旧同名节，保留其他内容，追加新节 |
| `remove_section(name)` | 删除指定节，保留其余；去除尾部空行 |

### `set_section` 细节

- 逐行复制旧内容，跳过目标节的旧行；遇到新节头时结束跳过。
- 追加 `[name]` 与各 `k=v` 行。
- 若 manifest 不存在，先写头部注释行。
- 写入须原子（临时文件 + rename）。

## 失败记录（安装编排约定）

模块安装失败时写：

```
[<module>]
installed=failed
failed_at=<ISO8601>
```

成功但模块未自写节时，编排层回退写 `installed=true`。模块若自写节（含自由字段），
编排层**不得**覆盖。

## 验收点（C3）

- `C3-init`：新建 manifest 含三顶层键，`schema_version=1`。
- `C3-state`：`true`/`false`/`failed`/`absent` 四种返回。
- `C3-set-section`：整节替换，其他节与顶层键保留。
- `C3-list-installed`：仅列出 `installed=true`。
- `C3-crlf`：CRLF 输入可解析。
- `C3-failed`：失败节含 `installed=failed` 与 `failed_at`。
