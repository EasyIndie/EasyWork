# 回滚指南（跨平台迁移期）

> 适用版本：M0–M7 迁移期（Bash 引擎冻结作 oracle，Go 引擎为主）。
> 原则：**用户数据格式不变**，因此实现可双向切换，无需迁移脚本。

## 数据兼容保证

Bash 与 Go 实现共享同一套契约（`docs/spec/`）：

| 数据 | 位置 | 兼容性 |
|---|---|---|
| 状态根 | `$EASYWORK_HOME`（默认 `~/.easywork`） | 相同 |
| 主配置 | `$EASYWORK_HOME/config.toml` | 相同（含转义） |
| 安装状态 | `$EASYWORK_HOME/manifest` | 相同 |
| 模块目标文件 | `~/.gitconfig`、`~/.vimrc`、`~/.sh_config_custom` | managed section 标记逐字节相同 |

因此从 Go 回退到 Bash（或反之）**不会**破坏已安装状态；重复 `install` 幂等。

## 回滚方式

### 1. 降级到指定旧版本（推荐）

```bash
EASYWORK_VERSION=0.1.0 \
  curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.sh | bash
```

`bootstrap.sh` 会按 `EASYWORK_VERSION` 拉取对应 tag 的二进制并覆盖安装。

### 2. 使用 Bash oracle（迁移期仍随仓库发布）

冻结的 Bash 引擎仍保留在 `bin/easywork`（仅安全修复，不加功能）：

```bash
git checkout <previous-tag>
./bin/easywork install --yes
```

或直接运行该 tag 的原始脚本：

```bash
curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/<previous-tag>/bin/easywork | bash
```

### 3. 完全卸载

```bash
ew uninstall --remove-config
```

## 验收与回归

回滚后应通过：

```bash
make check          # ShellCheck + shfmt + BATS（Bash 引擎）
make gotest         # Go 单元测试
make conform-bash   # 黑盒 conformance 对 Bash 版全绿
```

## Bash 引擎退役条件

- Go 引擎连续 ≥2 个 release 无回滚事故；
- `tests/conformance` 对两种实现全绿；
- 届时删除 `lib/*.sh` 与 `bin/easywork`，仅保留 `bootstrap.sh` + Go 二进制，
  并移除本指南。
