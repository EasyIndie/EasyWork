# AGENTS.md — EasyWork 开发指引（供 AI 编码代理阅读）

> 本文件供 pi / codex / claude code 等 AI 编码代理在进入本仓库时自动加载。
> 人类开发者请同时阅读 [README.md](README.md) 与 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 1. 项目一句话

**EasyWork**：Go 静态单二进制的开发环境一键配置 CLI（macOS / Linux / Windows），
终端用户零运行时依赖，`curl | bash`（Unix）或 `irm | iex`（Windows）即可用。
**Bash 引擎已于 0.4.0 退役**（存档 tag `legacy-bash-0.3.0`），现只有一套实现。

## 2. 技术约束（硬性，违反即不合格）

- **标准库优先**：Go 引擎不引入第三方运行时依赖（下载用 `net/http`，无 curl 依赖）；
  可接受编译期依赖，但需在设计文档留决策记录
- **跨三平台**：`GOOS=darwin|linux|windows`、`GOARCH=amd64|arm64` 必须全部编译通过；
  Windows 差异（路径、PROFILE、编码、进程创建）走 `internal/platform` 抽象
- **`gofmt` / `go vet` 全绿**；shell 脚本（`bootstrap.sh`、`scripts/*.sh`）必须过
  ShellCheck + `shfmt -i 4 -bn -ci -sr`
- **输出编码**：数据（JSON/版本号）走 stdout，日志走 stderr；`--json` 字节级稳定；
  Windows 控制台编码由 `platform.EnableUTF8Console` / `platform.ConsoleOutput` 处理，勿绕过
- **用户数据不变式**：`$EASYWORK_HOME/{config.toml,manifest}` 格式与 managed section 标记逐字节不变

## 3. 常用命令

```bash
make check        # lint + fmt-check + gotest + conformance + 安装链路（提交前必跑）
make gotest       # go test ./...
make test         # 黑盒 conformance（tests/conformance，仅 Go）
make lint         # ShellCheck（bootstrap.sh + scripts/）
make fmt          # shfmt -w
make build        # 构建到 .build/ew
make install      # 安装（Unix: /usr/local/bin 或 ~/.local/bin；Windows: %USERPROFILE%\.local\bin）
make install-e2e  # bootstrap + update 本地镜像端到端（不触网；Windows 用 scripts/bootstrap-e2e.ps1）
make acceptance   # 一键验收（静态检查/单测/conformance/交叉编译/安装链路/退役不变量）
make retire-check # 断言 Bash 引擎没有复活
```

## 4. 目录结构

```
cmd/ew/            # CLI 入口（console 编码适配在此完成）
internal/cli/      # 命令路由与各命令（status/install/keepawake/config/...）
internal/engine/   # 契约实现：config.toml / manifest / managed section / owned file / JSON
internal/modules/  # 模块（shell/git/gh/vim/ai + 可选 mole/herdr/glow/ghostty/keepawake）
internal/platform/ # 平台抽象（Env/PkgManager/Lock/AtomicWrite/Process/Power/Console）
internal/keepawake/ # 设备防休眠（电源断言 + 自启单元）
internal/release/  # 发布资产命名/校验/解包（update 自升级）
internal/version/  # 唯一版本来源
docs/spec/         # 契约规格（规范性，语言无关）
tests/conformance/ # 黑盒 conformance（唯一门禁，只测 Go）
scripts/           # 引导/安装/验收/端到端脚本
bootstrap.sh|.ps1  # 下载并安装二进制（唯一安装入口）
```

## 5. 架构要点

- **规范源**：`docs/spec/` 是语言无关契约，改行为先改规格，再改实现
- **模块契约**（`internal/modules/module.go`）：
  `Name()` / `Description()` / `Priority()` / `Platforms()` + `Install()` / `Uninstall()`；
  可选能力：`Optional() bool`（默认不在 `ew install` 装）、`Components()`（子组件）、
  `Aliases()`（兼容别名）。注册顺序 = `registry` 切片顺序 = `list` 输出顺序，
  新增模块请按名字字母序插入
- **幂等写入**：目标文件（`~/.gitconfig`、`~/.vimrc`、`.sh_config_custom`、`$PROFILE`）
  必须经 `engine.ApplyManagedSection`，用 `>>> EasyWork managed section begin/end` 包裹；
  plist/systemd unit 这类整体文件用 `engine.ApplyOwnedFile`（首次备份、卸载还原）
- **manifest**：`~/.easywork/manifest` 记录模块 `installed` 状态（ini 风格）
- **并发锁**：`platform.AcquireLock`（`O_CREATE|O_EXCL` + 陈旧回收）
- **安装编排**：`priority` 升序；可选模块仅显式指名才装；失败不阻塞后续模块并写 `failed`

## 6. 当前状态（0.4.0）

- ✅ 5 个契约 + managed section 协议 + 跨平台行为（`docs/spec/`）
- ✅ CLI/JSON 信封、`--json` 分流、退出码封闭集合
- ✅ 可选模块：`mole` / `herdr` / `glow` / `ghostty`（终端模拟器为 GUI 例外）
- ✅ 子组件细选（`ai/claude`、`claude` 简写）
- ✅ **设备防休眠 `keepawake`**（`docs/spec/08-keepawake.md`，C11）：只注册电源断言、
  零 sudo；五态 status；`--persist` 写自启单元
- ✅ Windows 原生：`$PROFILE` 注入、winget/scoop/choco、UTF-8 控制台与管道编码适配
- ✅ **Bash 引擎已退役**：`bin/` `lib/` `MODULES` `easywork.conf.example` 与 Bash 白盒测试已删除
- ❌ 明确不做：GUI 应用（终端模拟器除外）、editor、modern-shell、AI 会话编排器

## 7. 改动规则

1. **改契约前先改 `docs/spec/`**，再改实现。
2. **交互与执行分离**：`Install()` 内禁止交互；交互由 `ew install` 前端完成后写回 config。
3. **新增模块**：`internal/modules/xxx.go` → 加入 `registry`（字母序）→ 补 `*_test.go`
   → 视需要补 `tests/conformance/*.bats`。
4. **目标文件写入**只允许经 engine 的声明式函数，禁止模块手写备份/标记逻辑。
5. 新增功能必须补测试；改动后先跑 `make check`。
6. **不要恢复 Bash 引擎**；`make retire-check` 会拦。

## 8. 测试约定

- `make test` = `tests/conformance/run.sh go`：黑盒，通过 `$EW_BIN` 调用二进制，
  每个用例独立 `HOME`/`EASYWORK_HOME` 沙箱（`mktemp -d`），对 stdout 做字节级断言
- `tests/conformance/helpers.bash` 导出 `EASYWORK_OUTPUT_ENCODING=utf8`（保证跨平台字节稳定）
- 不发起真实网络：本地镜像端口由 `scripts/{bootstrap,update}-e2e.sh` 提供（127.0.0.1）
- Go 单测：纯函数与可注入依赖（`Runner`/`Clock` 等），不得改动宿主真实状态
  （如 keepawake 测试注入 fake runner，不真的起 caffeinate/launchctl）
- CI：`shell-lint`（shellcheck+shfmt）、`install-e2e`（三平台：Unix 跑 `bootstrap-e2e.sh`，
  Windows 跑 `bootstrap-e2e.ps1`）、`go-engine`（三平台 go test + conformance + Windows smoke）、
  `cross-compile`（6 目标）
- Windows 安装链路在 CI 上跑**两个宿主**：Windows PowerShell 5.1 与 PowerShell 7
  （`-ChildShell powershell|pwsh`），并额外覆盖文档里的 `irm | iex` 用法
- `scripts/bootstrap-e2e.ps1` 必须保持**纯 ASCII**：Windows PowerShell 5.1 会按 ANSI
  解析无 BOM 脚本，非 ASCII 文本可能破坏语法（CI 有专门断言）

## 9. 一句话风格要求

保持与现有代码一致：中文注释/日志、英文标识符、错误信息给出「可复制的修复命令」而非术语；
平台差异集中在 `internal/platform`，业务代码不出现 `runtime.GOOS` 分支散落。
