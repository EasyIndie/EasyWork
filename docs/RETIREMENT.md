# Bash 引擎退役清单

> 状态：**准备中（未执行）**。Bash 实现现作为迁移期的等价性 oracle（冻结，仅安全修复）。
> 退役前置条件满足后，按本清单一次性移除。

## 前置条件（须全部满足）

- [ ] Go 引擎已连续 **≥2 个 release** 无回滚事故
- [ ] `tests/conformance` 对 **Bash 与 Go** 均全绿（`bash tests/conformance/run.sh all`）
- [ ] `scripts/retire-check.sh` 通过（`make retire-check`）
- [ ] 用户数据兼容性无回归：`EASYWORK_HOME` / `config.toml` / `manifest` 双向可读
- [ ] `bootstrap.sh` 默认（无镜像）路径在真实 release 上验证通过

## 退役步骤

1. **打存档 tag**：`git tag -a legacy-bash-<ver>`，保证可回到 Bash 实现。
2. **删除 Bash 引擎**：
   - `bin/easywork`
   - `lib/common.sh`、`lib/install.sh`、`lib/completions.sh`、`lib/shell.sh`、`lib/git.sh`、`lib/gh.sh`、`lib/vim.sh`、`lib/ai-tools.sh`
   - `MODULES`（管道 Bash 安装索引，Go 不再使用）
3. **更新入口**：
   - `bootstrap.sh` 为唯一 `curl | bash` 入口（已具备）
   - `release.yml` 移除 bash 资产与 `bin/easywork`/`lib/*.sh` 校验（保留二进制矩阵 + checksums + attestation）
   - 删除 `easywork.conf.example`（旧 ini 示例）
4. **测试收敛**：
   - 删除 `tests/test_*.bats`（Bash 白盒/集成）与 `tests/helpers/mocks.bash`
   - 保留并扩至唯一门禁：`tests/conformance/*.bats`（只测 Go）
   - `tests/conformance/run.sh` 仅保留 `go` 分支；`run.sh` 的 Bash unset/mocks 相关逻辑清理
5. **构建与检查**：
   - Makefile：移除 `conform-bash`、`dry-run`（基于 Bash）；`check` 纳入 `gotest` + `conform`
   - CI：移除 `lint-and-test` 中的 Bash 步骤，保留 ShellCheck（仅 `bootstrap.sh`/`scripts/`）与 `go-engine`
   - `release.yml` 的 ShellCheck/Syntax/BATS/dry-run 步骤移除
6. **文档**：
   - `AGENTS.md`、`README.md`、`DESIGN.md`、`docs/ACCEPTANCE.md`、`docs/ROLLBACK.md` 去掉 Bash 引擎描述，指明只剩 Go 引擎
   - 本清单标记为「已执行」并归档

## 回滚点

- 退役前打 `legacy-bash-<ver>` tag；如需回退，恢复该 tag 并重新发布 Bash 资产。
- 用户侧无数据迁移：`bootstrap.sh` 安装的 Go 二进制读取同一 `EASYWORK_HOME`。

## 不变量（退役不得破坏）

- `~/.easywork/config.toml`、`~/.easywork/manifest` 格式与路径不变。
- 模块目标文件（`~/.gitconfig`、`~/.vimrc`/`_vimrc`、`.sh_config_custom`/`$PROFILE`）
  的 managed section 标记逐字节不变。
- CLI 契约（`docs/spec/`）不变。
