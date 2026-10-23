# 验收指南

> 适用于当前 **Go 单引擎**实现。可自动化部分由 `scripts/acceptance.sh` 一键执行：
>
> ```bash
> make acceptance        # = bash scripts/acceptance.sh
> ```

脚本按顺序执行并汇总 `PASS / FAIL / SKIP`（工具缺失记 SKIP，不算失败；有 FAIL 则退出码 1）。

## 验收项

| 项 | 判据 |
|---|---|
| ShellCheck | `bootstrap.sh` + `scripts/*.sh` 零告警 |
| shfmt | `shfmt -d -i 4 -bn -ci -sr .` 无差异 |
| Go vet + 单测 | `go vet ./...`、`go test ./...` 全绿 |
| Conformance | `tests/conformance/run.sh go` 全绿（73 用例） |
| 交叉编译 | 6 目标 `{darwin,linux,windows}×{amd64,arm64}` 构建成功 |
| 端到端冒烟 | 沙箱内 `status --json` → `keepawake status --json` → `install git shell` → 写入 managed section → `uninstall` 后标记消失 |
| 退役不变量 | `make retire-check`：无 Bash 残留、`bootstrap.sh` 带 sha256 校验、发布链路只针对 Go |
| 安装链路 | `bootstrap-e2e`（Unix）/ `bootstrap-e2e.ps1`（Windows，PowerShell 5.1 与 7 各一次，含 `irm \| iex`）+ `update-e2e`；全部访问 127.0.0.1 本地镜像，不触网 |

## 分项命令

```bash
# 静态检查与单测
make lint && make fmt-check && make gotest

# 黑盒 conformance（每个用例独立 HOME/EASYWORK_HOME 沙箱，stdout 字节级断言）
make test

# 安装 / 升级链路（本地镜像：指定版本、latest 解析、sha256 篡改拦截、自升级）
make install-e2e

# 交叉编译 + 端到端 + 退役不变量
make acceptance
```

## CI 对应关系

每次迭代的反馈速度由任务分层决定（详见 [ITERATION.md](ITERATION.md)）：

| 任务 | 何时跑 | 覆盖 |
|---|---|---|
| `Changed paths` | 每次 push / PR | 判定是否只有 docs/site/markdown 改动（纯文档跳过重矩阵） |
| `Quick gate` | 每次 push / PR（~1–2 分钟） | Ubuntu：ShellCheck + `bash -n` + shfmt + `gofmt` + `go vet` + `go test` + Go conformance |
| `Shell lint (macos-latest)` | main 推送 + 有代码改动 | macOS 自带 bash 3.2 语义下 ShellCheck + shfmt |
| `Install chain e2e` | main 推送 + 有代码改动 | Ubuntu / macOS / Windows：`bootstrap-e2e.sh` 或 `bootstrap-e2e.ps1`（Windows 用 PS 5.1 与 7 各一次）+ `update-e2e` |
| `Go engine (macos/windows)` | main 推送 + 有代码改动 | 平台差异：`go test` + `gofmt`/`go vet` + Go conformance + Windows 原生冒烟 |
| `Cross-compile` | main 推送 + 有代码改动 | 6 目标交叉编译 |
| `Pages` | `site/**` 改动 | 产品页：`site/` 直接部署到 GitHub Pages（自定义域名 `easywork.jokerhub.cn`） |
| `release` / `binaries` / `checksums` | 打 tag `x.y.z` | 6 目标二进制 + `checksums.txt` + build provenance attestation |

- PR 上只跑 `changed paths` + `quick`：合入前反馈 ≤ 2 分钟；
- 需要只跑一次快车道：`gh workflow run ci.yml -f scope=fast`；
- 同一分支的新推送会取消旧运行（`concurrency.cancel-in-progress`）。

## 迁移期历史（已结束）

0.1.0–0.3.0 期间存在 Bash 与 Go 双实现，用同一套 conformance 做字节等价校验；Bash 在
0.4.0 退役（存档 tag `legacy-bash-0.3.0`）。相关决策见 `DESIGN.md` §12/§15，执行记录见
[RETIREMENT.md](RETIREMENT.md)。
