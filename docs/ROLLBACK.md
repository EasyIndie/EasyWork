# 回滚指南

> 当前状态：**仅 Go 引擎**（Bash 引擎已于 0.3.0 退役，存档 tag `legacy-bash-0.3.0`）。
> 原则：**用户数据格式不变**，因此可以在不同 Go 版本间自由升降级，无需迁移脚本。

## 数据兼容保证

| 数据 | 位置 | 兼容性 |
|---|---|---|
| 状态根 | `$EASYWORK_HOME`（默认 `~/.easywork`） | 0.1.0 起不变 |
| 主配置 | `$EASYWORK_HOME/config.toml` | 不变（含转义规则） |
| 安装状态 | `$EASYWORK_HOME/manifest` | 不变 |
| 模块目标文件 | `~/.gitconfig`、`~/.vimrc`、`.sh_config_custom`/`$PROFILE` | managed section 标记逐字节不变 |
| 防休眠运行态 | `$EASYWORK_HOME/run/keepawake.json` | 易失；缺失只影响 `status` 显示，不影响配置 |

升降级后重复 `install` 幂等，不会产生重复 section。

## 回滚方式

### 1. 降级到指定旧版本（推荐）

```bash
EASYWORK_VERSION=0.2.1 \
  curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.sh | bash
```

`bootstrap.sh` 会按 `EASYWORK_VERSION` 拉取对应 tag 的二进制、校验 sha256 后覆盖安装。

### 2. 从源码构建指定 tag

```bash
git checkout <tag>
make build && make install
```

### 3. 完全卸载

```bash
ew uninstall --remove-config    # 移除 managed section 并删除配置
# 防休眠残留（若曾 --persist）：
ew keepawake off
```

### 4. 回退到 Bash 引擎（仅历史参照）

Bash 实现已归档在 tag `legacy-bash-0.3.0`，仅作行为参照，**不再发布资产**：

```bash
git show legacy-bash-0.3.0:bin/easywork > /tmp/easywork-legacy
git show legacy-bash-0.3.0:lib/common.sh   # 需要时按需取出
```

注意：该版本不含 `keepawake`、不支持 Windows 原生、无 UTF-8 管道适配。

## 验收与回归

```bash
make check        # ShellCheck + shfmt + go test + conformance + 安装链路
make acceptance   # 全量验收（含交叉编译、退役不变量）
```

回滚相关改动后至少跑 `make check`；涉及发布/引导链路的改动加跑 `make install-e2e`。
