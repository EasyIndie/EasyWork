# 文件协议：Managed Section

> 规格编号：C6 ｜ 对应 DESIGN §6.2 ｜ 状态：冻结

## 目的

让 EasyWork 可幂等地向用户已有配置文件（`~/.gitconfig`、`~/.vimrc`、
`~/.sh_config_custom`、shell rc）注入内容，卸载时可精确移除并还原原文件。

## 标记文本（逐字节固定）

```
<comment> >>> EasyWork managed section begin (v<version>) >>>
<content>
<comment> <<< EasyWork managed section end <<<
```

- `<comment>`：`#`（默认）或 `"`（Vim 用）。
- `<version>`：写入时的工具版本。
- 三段各占一行，行尾 `\n`。

**检测规则（注释无关）**：只要文件中某行包含子串 `managed section begin`
（或 `managed section end`）即视为标记行。`<comment>` 前缀不参与匹配，
以兼容跨版本/跨注释风格。

## 操作：Apply

`Apply(target, version, content, comment) -> (backupPath|nil, error)`

1. **备份**：若 `target` 存在，且**不包含**子串 `EasyWork managed section`，
   则复制到 `target.bak.<stamp>`，`<stamp> = %Y%m%dT%H%M%S`（本地时间），
   并返回该备份路径；否则不备份。
2. **文件不存在**：创建，内容为 `begin` + `content` + `end`。
3. **已存在 managed section**（含 `managed section begin`）：逐行复制，
   将 `begin..end`（含）替换为新的 `begin` + `content` + `end`；
   区段外的行**原样保留**。
4. **存在但无 managed section**：前置写入 `begin` + `content` + `end` +
   一个空行 + 原文件全部内容。

### 备注

- 第 1 步的备份判定用 `EasyWork managed section`（含 `EasyWork`），第 3 步的
  替换判定用 `managed section begin`。实现须保持此差异，以兼容历史文件。
- 写入须原子（临时文件 + rename）。
- 若 `content` 为空，仍写入空的 begin/end 对。

## 操作：Remove

`Remove(target, backupPath?) -> ok`

1. `target` 不存在，或无 `managed section begin` → 成功 no-op。
2. 删除 `begin..end`（含）区间，保留其余行。
3. **畸形段**（有 begin 无 end）：警告，**不修改文件**，返回失败。
4. 若提供 `backupPath` 且文件存在：用备份覆盖 `target`（`mv` 还原）。

## 幂等性（不变量）

- 对同一 `target` 连续两次 `Apply` 相同 `content`，结果字节完全一致。
- `Apply` 后 `Remove` 应恢复出与原始无 section 文件等价的内容（若曾备份则精确还原）。

## 备份命名

- 备份文件名：`<target>.bak.<%Y%m%dT%H%M%S>`，与目标同目录。
- 保留属性（复制 mtime 等，Unix `cp -p`）。
- 用户自行删除备份文件不影响后续操作（还原时文件不存在则跳过并返回失败，被编排层忽略）。

## 验收点（C6）

- `C6-create`：目标不存在 → 生成仅含 begin/content/end 的文件。
- `C6-prepend`：目标存在且无 section → section 在前、空行、原文在后。
- `C6-replace`：已有 section 被替换，区段外内容逐字节不变。
- `C6-idempotent`：两次 Apply 字节一致。
- `C6-remove`：移除 section，保留用户内容。
- `C6-malformed`：缺 end 时不修改并报告失败。
- `C6-backup-restore`：Apply 备份后 Remove 精确还原原文件。
- `C6-comment`：`"` 注释风格标记正确（Vim）。
