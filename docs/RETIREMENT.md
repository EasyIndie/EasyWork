# Bash 引擎退役记录

> 状态：**已执行（2026-10-23，v0.4.0）**
> 存档 tag：`legacy-bash-0.3.0`（退役前最后一个双引擎提交）
> 结论：`make retire-check` 断言不变量成立，Bash 引擎与相关白盒测试已彻底移除。

## 执行时的前置条件核对

- [x] Go 引擎已连续 ≥2 个 release 无回滚事故（0.2.0 / 0.2.1）
- [x] `tests/conformance` 对 Bash 与 Go 均全绿（130 项 / 65×2）
- [x] `scripts/retire-check.sh`（旧版，前置检查）通过 8/8
- [x] 用户数据兼容性无回归：`EASYWORK_HOME` / `config.toml` / `manifest` 双向可读
- [x] `bootstrap.sh` 默认路径有自动化端到端（新增 `scripts/bootstrap-e2e.sh`，见「退役前补的门禁」）

## 退役前补的两道门禁

退役会让 `bootstrap.sh` 成为 Unix 唯一安装入口，因此先补齐：

1. **`scripts/bootstrap-e2e.sh`**：本地镜像（127.0.0.1）验证
   ① 指定版本安装 ② 经 API 解析 latest ③ 归档被篡改时必须失败且不覆盖已装二进制；
   同时给 `bootstrap.sh` 增加了 sha256 校验（此前只下载不校验）。
2. **`scripts/update-e2e.sh` 接入 CI**（新增 `install-e2e` job），并让 `make check` 覆盖安装/升级链路。
   同一 job 的 Windows 矩阵跑 `scripts/bootstrap-e2e.ps1`（`bootstrap.ps1` 亦补上 sha256 校验），
   使两平台安装入口都有自动化门禁。

另外把 Bash 白盒测试里未被 conformance 覆盖的 4 条行为断言迁入规格测试：
`C4-init-installs-shell-and-git`、`C5-install-single-module`、
`C6-uninstall-partial-keeps-others`、`C6-dry-run-writes-nothing`
（最后一条暴露了 Bash 在 `--dry-run` 下误写 `installed=true` 的缺陷；Go 行为正确，故该用例为 Go-only）。

## 已执行的步骤

1. **打存档 tag**：`legacy-bash-0.3.0`。
2. **删除 Bash 引擎**：`bin/easywork`、`lib/*.sh`、`MODULES`、`easywork.conf.example`。
3. **删除 Bash 白盒测试**：`tests/test_*.bats`（192 用例）、`tests/helpers/mocks.bash`、`tests/run.sh`。
4. **收敛入口**：`bootstrap.sh`（Unix）/ `bootstrap.ps1`（Windows）为唯一安装入口。
5. **发布链路**：`release.yml` 移除 Bash 资产与对应的 `.sha256` 校验，仅发布二进制矩阵 +
   `checksums.txt` + attestation。
6. **CI**：`lint-and-test`（跑 Bash 全套）→ `shell-lint`（只检查 `bootstrap.sh` + `scripts/*.sh`）；
   conformance 步骤统一为 Go；保留 `install-e2e`、`go-engine`（三平台）、`cross-compile`。
7. **Makefile**：删除 `conform-bash` / `conform(all)`，`check` 收敛为
   `lint + fmt-check + gotest + test(conformance) + install-e2e`。
8. **文档**：`AGENTS.md`（重写为 Go 单引擎）、`README.md`、`CONTRIBUTING.md`、
   `DESIGN.md`（加退役横幅与 §15）、`docs/ACCEPTANCE.md`、`docs/ROLLBACK.md`，
   以及 `docs/spec/04`、`05`、`README` 中「Bash 已冻结」类表述。
9. **`scripts/retire-check.sh` 语义反转**：从「退役前置检查」改为「退役不变量检查」
   （断言旧文件不复活、bootstrap 校验存在、release/CI/Makefile 无 Bash 资产）。

## 退役后的不变量（`make retire-check` 守护）

- `~/.easywork/config.toml`、`~/.easywork/manifest` 格式与路径不变；
- 模块目标文件的 managed section 标记逐字节不变；
- CLI 契约（`docs/spec/`）不变；
- 没有 `bin/`、`lib/`、`MODULES`、`easywork.conf.example`、`tests/test_*.bats`。

## 回滚点

`git checkout legacy-bash-0.3.0` 可取回全部 Bash 源码；如需重新发布 Bash 资产，
按该 tag 的 `release.yml` 恢复对应步骤。用户侧无数据迁移。
