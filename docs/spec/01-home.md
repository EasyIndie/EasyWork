# 契约一：状态根 `EASYWORK_HOME`

> 规格编号：C1 ｜ 对应 DESIGN §2 ｜ 状态：冻结

## 目的

统一工具自身的全部持久化状态，使安装可覆盖（用于沙箱/测试）、可迁移、可清理。

## 定义

```
EASYWORK_HOME := ${EASYWORK_HOME:-${HOME}/.easywork}
```

- 环境变量 `EASYWORK_HOME` 非空时**优先**。
- 否则 `HOME` 非空时用 `${HOME}/.easywork`。
- 否则（Windows 上 `HOME` 缺失）用当前用户主目录：`%USERPROFILE%\.easywork`。

## 布局（规范）

| 路径 | 用途 | 是否必须存在 |
|---|---|---|
| `${EASYWORK_HOME}/config.toml` | 主配置（契约二） | 首次写配置时创建 |
| `${EASYWORK_HOME}/config` | 旧 ini（只读回退，迁移后保留） | 否 |
| `${EASYWORK_HOME}/manifest` | 安装状态（契约三） | 安装时创建 |
| `${EASYWORK_HOME}/lib/v<version>/` | 管道模式库缓存（迁移期） | 否 |
| `${EASYWORK_HOME}/completions/` | shell 补全文件 | 安装补全时 |
| `${EASYWORK_HOME}/.last_update_check` | 更新检查缓存（2 行） | 检查后 |

### 不变量

- **工具状态只允许落在 `EASYWORK_HOME` 下**。任何硬编码 `~/.easywork` 之外的
  工具状态都是违规。
- **模块目标文件**（`~/.gitconfig`、`~/.vimrc`、`~/.sh_config_custom`、shell rc）
  位于 `HOME` 下，**不在** `EASYWORK_HOME` 下；通过覆盖 `HOME` 实现隔离。

## 路径派生（规范函数）

实现须提供等价的路径派生（命名可不同，语义必须一致）：

| 逻辑名 | 值 |
|---|---|
| `home()` | `EASYWORK_HOME` |
| `config_path()` | `${EASYWORK_HOME}/config.toml` |
| `legacy_config()` | `${EASYWORK_HOME}/config` |
| `manifest_path()` | `${EASYWORK_HOME}/manifest` |
| `lib_cache()` | `${EASYWORK_HOME}/lib/v${VERSION}` |
| `completions_dir()` | `${EASYWORK_HOME}/completions` |

路径一律使用平台路径分隔符（Windows 用 `\`，Unix 用 `/`）。

## 并发锁

对 `EASYWORK_HOME` 的写操作须串行化：

- 锁文件位于系统临时目录：`<tmp>/easywork.lock`，`<tmp>` 取平台临时目录
  （Unix `TMPDIR`/`/tmp`，Windows `%TEMP%`）。
- 获取顺序（Unix）：`flock` → `shlock` → `mkdir`；超时默认 30s。
- Windows：`O_CREATE|O_EXCL` 锁文件 + 陈旧检测。
- 超时返回退出码 `5`（`EXIT_LOCK`）。
- 释放锁为幂等操作。

## 验收点（C1）

- `C1-home-default`：未设 `EASYWORK_HOME` 时派生 `${HOME}/.easywork`。
- `C1-home-override`：设置 `EASYWORK_HOME` 后所有路径跟随。
- `C1-paths`：六个路径派生函数的返回值。
- `C1-isolation`：仅覆盖 `HOME` 即可完全隔离，`EASYWORK_HOME` 缺省跟随。
- `C1-lock`：并发获取第二个锁超时返回 `5`；释放后可再次获取。
