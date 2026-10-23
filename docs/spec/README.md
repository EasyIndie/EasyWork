# EasyWork 接口规格（语言无关 ABI）

> 状态：**M1 冻结（normative）**
> 本目录是 EasyWork 的**规范性接口规格**。任何实现（当前 Go 单二进制，未来其他）
> 只要满足本规格，即可视为行为等价的 EasyWork。
>
> 与 [`DESIGN.md`](../../DESIGN.md) 的关系：DESIGN 是设计蓝图与决策记录；本规格是
> **可执行契约**，是黑盒 conformance 测试（`tests/conformance/`）的唯一判据。
> 冲突时以本规格为准；修改契约须先改本目录，再改实现。

---

## 契约清单

| # | 契约 | 规格 | 关键不变量 |
|---|---|---|---|
| 1 | 状态根 `EASYWORK_HOME` | [01-home.md](01-home.md) | 工具状态只落在 `EASYWORK_HOME` 下 |
| 2 | 声明式配置 `config.toml` | [02-config-toml.md](02-config-toml.md) | TOML v1 子集；`cfg_*` 语义固定 |
| 3 | 安装状态 `manifest` | [03-manifest.md](03-manifest.md) | ini 风格；`installed` 取值封闭 |
| 4 | CLI 与 JSON 输出 | [04-cli-json.md](04-cli-json.md) | 字节级固定的 JSON 信封 |
| 5 | 模块接口与声明式引擎 | [05-module-interface.md](05-module-interface.md) | 模块只声明，引擎负责写盘 |
| 6 | Managed section 文件协议 | [06-managed-section.md](06-managed-section.md) | 标记文本逐字节固定，幂等 |
| 7 | 跨平台行为 | [07-cross-platform.md](07-cross-platform.md) | 平台差异边界固定 |
| 8 | 设备防休眠 `keepawake` | [08-keepawake.md](08-keepawake.md) | 只注册电源断言，不改系统策略；`status` 报告真实断言 |

---

## 契约变更记录（相对 v2 Bash 实现）

| 变更 | 说明 |
|---|---|
| **允许编译期依赖** | “零运行时依赖”重定义为：**终端用户零运行时依赖**（静态单二进制）。实现可引入编译期依赖（如 Go module、TOML 库）。Bash 实现仍不得引入运行时依赖。见 DESIGN §12.2。 |
| **平台能力声明** | 模块新增“支持平台集合”，见 [05](05-module-interface.md#平台能力)。 |
| **版本单一来源** | 唯一来源为 `internal/version/version.go`；release 由 ldflags 注入 tag。已删除 `VERSION` 文件与 Bash 常量。见 DESIGN §12.5。 |

---

## 通用约定

以下约定适用于全部契约，实现必须满足：

- **字符编码**：所有生成文件为 UTF-8，无 BOM。
- **换行**：所有生成文件统一 **LF**（Git for Windows / PowerShell 7 / Vim 均能解析）；
  输入解析同时接受 CRLF。为跨平台契约一致，不做 CRLF 转换。
- **路径展示**：JSON 输出中的路径统一使用 `/` 分隔（Windows 亦如此）；实际文件操作用 OS 原生分隔符。
- **stdout/stderr 分离**：日志与进度一律 stderr；数据（JSON/版本号）走 stdout。
  见 [04](04-cli-json.md#日志与数据分流)。
- **退出码**：`0` 成功 / `1` 通用错误 / `2` 缺依赖 / `3` 网络 / `4` 权限 / `5` 锁 /
  `130` 中断（SIGINT）。
- **幂等**：任何写操作重复执行结果一致（见 [06](06-managed-section.md)）。
- **原子写**：写目标文件一律“临时文件 + rename”，避免半写状态。
- **并发**：通过锁文件串行化（见 [01](01-home.md#并发锁)）。

---

## Conformance 测试分类

黑盒测试编号与规格条目一一对应；实现必须全部通过（Bash 引擎已于 0.3.0 退役，门禁只剩 Go）：

| 前缀 | 覆盖 | 位置（M1 起） |
|---|---|---|
| `C1-*` | 路径派生、`EASYWORK_HOME` 覆盖 | `tests/conformance/home.bats` |
| `C2-*` | config.toml 解析/写入/校验/迁移 | `tests/conformance/config.bats` |
| `C3-*` | manifest 读写/状态/失败记录 | `tests/conformance/manifest.bats` |
| `C4-*` | CLI 路由、JSON 信封、退出码、日志分流 | `tests/conformance/cli.bats` |
| `C5-*` | 模块注册/排序/能力/安装卸载 | `tests/conformance/modules.bats` |
| `C6-*` | managed section 写入/替换/移除/备份还原 | `tests/conformance/managed.bats` |
| `C7-*` | 跨平台行为（路径/包 ID/Vim/doctor） | 单测 + Windows 实机 |
| `C8-*` | shell 补全 setup/status/remove | `tests/conformance/c8_completion.bats` |
| `C9-*` | update 自升级（离线退出码 + 本地镜像端到端） | `tests/conformance/c9_update.bats` |
| `C10-*` | JSON 错误信封（`ok:false` + code/message） | `tests/conformance/c10_json_error.bats` |
| `C11-*` | 设备防休眠（`on`/`off`/`status`、`--dry-run`、可选模块标注） | `tests/conformance/c11_keepawake.bats` |

测试必须：在独立 `HOME`/`EASYWORK_HOME` 沙箱运行；不发起真实网络；对 stdout 做
**字节级**断言；对生成文件做规范化后的 golden 断言。
