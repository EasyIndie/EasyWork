# 验收指南

> 适用于 **Go 单引擎**（Bash 引擎已于 0.4.0 退役，见 [RETIREMENT.md](RETIREMENT.md)）。
> 验收 = 逐项满足下方判据，可自动化部分由 `scripts/acceptance.sh` 一键执行。
> 下方 M0–M7 保留为迁移期历史判据。

---

## 一键验收

```bash
scripts/acceptance.sh      # 或 make acceptance
```

脚本依次执行并在末尾汇总 `PASS/FAIL/SKIP`：

| 验收项 | 判据 | 对应阶段 |
|---|---|---|
| ShellCheck | `bootstrap.sh` + `scripts/*.sh` 零告警 | 质量门禁 |
| shfmt | 仓库级 `shfmt -d -i 4 -bn -ci -sr .` 无差异 | 质量门禁 |
| Go vet + test | `go vet ./...`、`go test ./...` 全绿 | M2 |
| Conformance | `tests/conformance/run.sh go` 全绿（69 用例） | M1/M2/M3 |
| 交叉编译 | 6 目标 `{darwin,linux,windows}×{amd64,arm64}` 全部构建成功 | M5 |
| Go 端到端 | 沙箱内 `status → keepawake status → install git shell → 标记存在 → uninstall → 标记消失` | M3/M6 |
| 退役不变量 | `make retire-check`：无 Bash 残留、bootstrap 带校验、发布链路只针对 Go | 退役后 |
| 安装链路 | `bootstrap-e2e`（Unix）/ `bootstrap-e2e.ps1`（Windows，PS 5.1 与 7 双宿主，含 `irm \| iex`）+ `update-e2e`，本地镜像不触网 | M5/M6 |

退出码 `0` 表示无 FAIL（工具缺失记为 SKIP，不算失败）。

---

## 分阶段验收判据

### M0 决策

> M0 的 spike 已在 M2 后删除；其能力（Bash↔Go 字节等价）由 conformance 套件承接。

### M1 规格 + conformance（迁移期先对 Bash 全绿，现已只跑 Go）
```bash
bash tests/conformance/run.sh go     # 当前唯一门禁
# 历史：迁移期曾用 EW_ENGINE=bash 对 Bash 版跑同一套 conformance（存档 tag legacy-bash-0.3.0）
```

### M2/M3 Go 引擎与模块
```bash
bash tests/conformance/run.sh go     # Go 版全绿
make gotest
```

### M4 Windows 原生执行
本地 macOS/Linux 无法执行 PE 二进制，由 CI 的 `go-engine` 任务在
`windows-latest` 上验证：
1. Go 单测 + `gofmt` + `go vet`；
2. **Go-only conformance**（`tests/conformance/run.sh go`，Bash 已冻结不参与）；
3. 原生冒烟：`status --json`、`list --json`（含 `ai` 与 `optional`）、`config set/get`、
   `install shell git` 在 PowerShell profile / `.gitconfig` 写 managed section。

> Windows 下 Unix-only 用例已自动处理：`shell`/`completion` 断言改为 PowerShell profile；
> 无法用无扩展名脚本 mock 的用例（mock npm）自动 skip；路径断言用 `cygpath -m` 对齐
> MSYS 对原生进程的环境变量路径转换。
>
> 真机实测（Windows 11 + Git Bash + bats-core）：**57/57 通过，1 skip**。

在真实 Windows 上的手工验收（先把 CLI 装到 PATH：Git Bash 中运行 `make install`
或 `bash scripts/install.sh`，会写入 `~/.local/bin` 并确保 PATH/PATHEXT）：
```powershell
# PowerShell
$env:EASYWORK_HOME = "$env:TEMP\ew-accept"
go build -o $env:TEMP\ew.exe ./cmd/ew
& $env:TEMP\ew.exe status --json --offline
& $env:TEMP\ew.exe install shell git --yes --offline
Select-String -Path $PROFILE -Pattern 'managed section'
& $env:TEMP\ew.exe uninstall shell git --yes --offline
```

### M5 二进制发布
```bash
make build          # 本机构建
make acceptance     # 含 6 目标交叉编译矩阵
```

发布后验收（对已发布 tag）：
```bash
VERSION=0.1.0
curl -fsSLO "https://github.com/EasyIndie/EasyWork/releases/download/${VERSION}/checksums.txt"
sha256sum -c checksums.txt        # 校验下载的归档
tar -xzf "easywork_${VERSION}_$(uname -s | tr 'A-Z' 'a-z')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz"
./ew version --json --offline
```

### M6 分发与向后兼容
```bash
bash -n bootstrap.sh
shellcheck bootstrap.sh
# Windows（本机可复现，不触网）：PS 5.1 与 PowerShell 7 各跑一次
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap-e2e.ps1 -ChildShell powershell
pwsh -NoProfile -File scripts/bootstrap-e2e.ps1 -ChildShell pwsh
# Windows 原生引导（真机/CI）：PowerShell 5.1 与 7 均可
#   $env:EASYWORK_VERSION='0.2.0'; $env:EASYWORK_DOWNLOAD_BASE='<mirror>'
#   Invoke-Expression (Get-Content -Raw bootstrap.ps1)   # 等价于 irm ... | iex
# 老用户数据无感：EASYWORK_HOME/config.toml/manifest 格式自 0.1.0 起不变
# Bash 引擎用户迁移：Bash 已于 0.4.0 退役，改用 bootstrap 一行命令安装 Go 二进制即可
```

### M7 矩阵 / 回滚
- CI：`shell-lint`（Ubuntu/macOS）、`install-e2e`、`go-engine`（三平台）、`cross-compile`（6 目标）。
- 回滚：见 [ROLLBACK.md](ROLLBACK.md)，回滚后重跑 `scripts/acceptance.sh`。

---

## Windows 实机验收记录

> 主机 `LAPTOP-APCBNCLR`（Windows 11 `10.0.26200`，AMD64，PowerShell 7.6.6），
> 通过 `ssh win` 执行。工具链：Go 1.27.2（`E:\go`，SHA256 校验通过）、git 2.54、winget 1.29。
> 代码同步至 `E:\EasyWork`。

| 验收项 | 命令 | 结果 |
|---|---|---|
| Go vet / 单测 | `go vet ./...`、`go test ./...`（在 Windows 上） | ✅ rc=0 |
| 构建 | `go build -o ew.exe ./cmd/ew` | ✅ |
| `version --json` | `ew.exe version --json --offline` | ✅ 合法信封 |
| `config set/get` | `config set …name` → `get` | ✅ 往返正确 |
| 安装 shell/git | `install shell git --yes --offline` | ✅ 写入 `$PROFILE` 与 `.gitconfig` 的 managed section |
| 幂等 | 重复 `install git` | ✅ 文件 SHA256 不变 |
| 卸载（逐组件） | `uninstall git` / `uninstall shell` | ✅ 标记均被移除 |
| 状态 | `status --json --offline` | ✅ 两模块 `true` → `absent` |
| 交叉编译（从 Windows） | 6 目标 `{darwin,linux,windows}×{amd64,arm64}` | ✅ 全部构建成功 |
| 跨平台发布物执行 | Unix 交叉编译的 `easywork_0.1.0_windows_amd64.exe` scp 至 Windows 运行 | ✅ SHA256 一致、`version`/`config`/`install` 正常 |

补充说明：

- `uninstall` 按 spec §5.1 为**单组件**（`uninstall <module>`）；不带参数则卸载全部。
  多参数调用仅第一个生效（与 Bash 实现一致）。
- 实机保留 `E:\go` 与 `E:\EasyWork`，便于后续回归；临时归档已清理。

### Bootstrap（`curl | bash`）端到端验收

由于仓库尚未发布带二进制的 release，采用**本地 HTTP 镜像源**（`EASYWORK_DOWNLOAD_BASE`）
验证 `bootstrap.sh` 全流程；版本解析则走真实 GitHub API。

| 项 | 结果 |
|---|---|
| macOS 引导（`darwin/amd64`） | ✅ 下载 tar.gz → 解压 → 安装 `ew` + `easywork` 软链 → 运行 |
| Windows 引导（Git Bash，`windows/amd64`） | ✅ 下载 zip → 解压 → 安装 `ew.exe` + `easywork.exe` → 运行 |
| 版本解析（GitHub API） | ✅ 未指定版本时解析出 `0.1.0` 并从镜像下载 |
| Go 网络更新检查 | ✅ `version --json` 含 `update.latest=v0.1.0`；`ew update` 写入缓存 |
| EXIT 清理 | ✅ 临时目录正确删除（修复 `tmp` 局部变量导致 trap 报错） |
| HTTP 镜像安全 | ✅ 默认强制 HTTPS；仅显式 `http://` 基址时允许并打印警告 |

> 网络环境：该机系统代理开关为关，但直连 HTTPS 已可通（`api.github.com` 200）；
> `git`/`go` 直连即可，无需额外代理配置。

### 跨平台适配验收（C7）

| 项 | 结果 |
|---|---|
| `doctor` 按平台生成 | ✅ Windows：`git/curl/node/npm/network`；Unix：`curl/git/awk/sed/zsh/network` |
| JSON 路径统一 `/` | ✅ Windows `status --json` 输出 `E:/EasyWork/...`，与 Unix 契约一致 |
| Vim 路径平台化 | ✅ Windows 写 `_vimrc` + `vimfiles/undo`；卸载后 marker 移除（`_vimrc` 置空，与 Unix 同语义） |
| 包 ID 映射 | ✅ `TestPackageNameMapping`（winget `GitHub.cli`、`BurntSushi.ripgrep.MSVC`、`OpenJS.NodeJS.LTS`） |
| `completion`（三平台） | ✅ `setup`/`status`/`remove`；macOS 注入 `.zshrc`+`.bash_profile`，Windows 注入 PowerShell `$PROFILE` |
| `vim` 对等 | ✅ vimrc 含 18 个 `Plug`；`plug#begin('…/vimfiles/plugged')`；创建 `vimfiles/{plugged,undo}`；Node/ripgrep 探测 |
| `update` 自升级 | ✅ macOS/Windows 本地镜像端到端：`0.1.0 → 0.2.0`，SHA256 校验，Windows 先改名再换入并清理 `.old` |
| JSON 错误信封 | ✅ `--json` 失败输出 `{"ok":false,...,"error":{"code","message"}}`；成功仍 `"error":null`；不产生副作用 |
| `install` 交互向导 | ✅ 伪终端下询问 Git 身份（≤2 问）并写回 config；非 tty 不提示 |
| 换行统一 | ✅ 统一 LF（规格已注明；工具均可解析） |

详见 [`docs/spec/07-cross-platform.md`](spec/07-cross-platform.md)。

## CI 对应关系

| 任务 | 位置 | 覆盖 |
|---|---|---|
| `shell-lint` | `.github/workflows/ci.yml` | ShellCheck + `bash -n` + shfmt（`bootstrap.sh` + `scripts/`，Ubuntu/macOS） |
| `install-e2e` | 同上 | 三平台：`bootstrap-e2e.sh` / `bootstrap-e2e.ps1`（含 sha256 篡改拦截；Windows 分别用 PS 5.1 与 pwsh 7 各跑一次）+ `update-e2e`，本地镜像不触网 |
| `go-engine` | 同上 | Go 单测 + `gofmt`/`go vet` + conformance（三平台）+ Windows 原生冒烟 |
| `cross-compile` | 同上 | 6 目标（darwin/linux/windows × amd64/arm64）交叉编译（PR/push） |
| `release` / `binaries` / `checksums` | `release.yml` | 6 目标二进制 + checksums + attestation（Bash 资产随 0.3.0 发布后于 0.4.0 移除） |

---

## 决策归档（#11–#13）

| 编号 | 结论 | 依据 |
|---|---|---|
| #11 Windows 程度 | WSL2/Git Bash 保底；**原生 PowerShell + winget 为终态** | DESIGN §12.1；`shell` 模块 Windows 分支 |
| #12 双实现成本 | 迁移期**接受**（Bash 冻结为 oracle，≤2 release）；**已于 0.4.0 退役** | `docs/RETIREMENT.md`；conformance 收敛为 Go |
| #13 签名/公证 | 第一版仅 sha256 checksums + provenance attestation；付费签名推迟到 1.0 后 | `release.yml` checksums 任务 |
