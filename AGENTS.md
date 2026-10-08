# AGENTS.md — EasyWork 开发指引（供 AI 编码代理阅读）

> 本文件供 pi / codex / claude code 等 AI 编码代理在进入本仓库时自动加载。
> 人类开发者请同时阅读 [README.md](README.md) 与 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 1. 项目一句话

**EasyWork**：纯 Bash 的开发环境一键配置 CLI（macOS / Linux），零运行时依赖，
`curl | bash` 即可用。当前处于 **v2 改造期**，目标是同时服务「人」与「AI agent」两类用户。

## 2. 技术约束（硬性，违反即不合格）

- **Bash 3.2 兼容**（macOS 默认 bash）：禁用 `${var,,}`、关联数组、`{fd}>` 自动 fd、
  `readarray`/`mapfile`、`local -n` 等 4.0+ 特性
- **零运行时依赖**：核心不引入 jq/yq/node/python；config.toml 解析器必须内联自写
- **`set -euo pipefail`** 全程开启；关键操作必须检查返回值并给出明确错误信息
- **ShellCheck + shfmt** 必须通过（shfmt 参数：`-i 4 -bn -ci -sr`）
- **兼容 zsh 语法检查**（CI 中 `zsh -n` 跑一遍）

## 3. 常用命令

```bash
make check       # lint + fmt-check + test（提交前必跑）
make lint        # ShellCheck 静态分析
make test        # bats tests/ --recursive
make fmt         # 自动格式化
make dry-run     # ./bin/easywork install --dry-run --yes
./bin/easywork install --dry-run --yes   # 预览安装
```

## 4. 目录结构

```
bin/easywork       # CLI 入口：路径解析、模块发现、命令路由
lib/common.sh      # 核心库：日志/系统检测/下载/manifest/config/锁/模块注册
lib/install.sh     # install / uninstall 编排
lib/completions.sh # bash/zsh 补全生成与注入
lib/{shell,git,vim}.sh  # 三个模块（每个即一个开发环境组件）
tests/*.bats       # 139 个 BATS 用例（cli/e2e/modules/noninteractive/unit）
tests/helpers/mocks.bash  # mock 层：覆盖 HOME，mock curl/git/vim 等
MODULES            # 模块索引（管道安装时远程拉取）
DESIGN.md          # v2 蓝图（5 契约 + 人机体验 + 命令名）
```

## 5. 架构要点

- **模块契约**：每个 `lib/*.sh` 模块必须声明 `MODULE_NAME`/`MODULE_DESCRIPTION`/`MODULE_PRIORITY`，
  并实现 `module_install`/`module_uninstall`；可选 `module_check`/`module_status`/`module_doctor`
- **模块自动发现**：`_discover_modules` 扫描 `lib/*.sh`，跳过 common/completions/install 三个库文件
- **幂等写入**：所有目标文件（`~/.gitconfig` 等）写入必须经 `replace_managed_section`，
  用 `>>> EasyWork managed section begin/end` 标记包裹，保留用户已有内容
- **manifest**：`~/.easywork/manifest` 记录各模块 installed 状态（ini 风格 `[section]` + `key=value`）
- **并发锁**：flock → shlock → mkdir 三级回退，fd=200 兼容 bash 3.2
- **管道模式**：`IS_PIPED` 时从 GitHub 拉取库文件到 `~/.easywork/lib/v<版本>/` 缓存

## 6. 当前状态与进行中的改造（重要）

- **DESIGN.md 是 v2 蓝图**，已冻结 5 个契约 + 人机体验三原则 + 命令名 `ew`。
- **Batch 1～4 已完成**：
  - ✅ **契约一 `EASYWORK_HOME`** 统一 + `ew_*` 路径派生函数
  - ✅ **契约二 config.toml（主配置）**：`cfg_get`/`cfg_get_bool`/`cfg_set`/`cfg_valid` +
    `config_migrate`；`config_init` 创建 config.toml，旧 ini 仅作只读回退并自动迁移；
    `ew config get/set`
  - ✅ **契约三 manifest**：`schema_version` + `manifest_module_state`
  - ✅ **契约四 CLI/JSON**：`--json` 信封、`json_escape`、日志分流 stderr；
    `version`/`list`/`status`/`doctor` 支持 `--json`；无参数 = `status` 摘要
  - ✅ **契约五 模块引擎**：`remove_managed_section`/`apply_managed_file`/
    `remove_managed_file`/`apply_module_files`/`remove_module_files`（声明式）
  - ✅ **人机体验**：`ew init`（零交互轻量默认）、Git 身份自动探测不阻塞、
    shell 分层开关（提示符/OMZ/网络工具默认关）、移除模块快捷命令
  - ✅ **命令名**：`ew` 别名（安装时创建软链、补全覆盖 ew/easywork）
- ✅ **config.toml 完全取代旧 ini**：`config_init` 创建 config.toml；旧 `config`（ini）仅作只读回退，
  首次 `install` / `config edit` 自动迁移；`config get/set` 读写 config.toml
- ✅ **可选模块（定稿见 DESIGN.md §11）**：新增 `gh`（自动安装 GitHub CLI）、
  `ai-tools`（自动安装 claude code / codex / pi，经 npm，离线/禁用开关可控）
- ❌ **明确不做**：editor（GUI）、modern-shell（现代 CLI 增强）、AI 会话编排器/配置管理器
- 测试现状：183 个 BATS 用例；改完先跑 `make check`（shfmt 仅 CI 环境有）。

## 7. 改动规则

1. **改契约前先改 DESIGN.md**，再改代码。
2. **交互与执行分离**：`module_install` 内禁止 `read -r -p`；
   交互一律由 `install` 前端在调用前完成并写回 config。
3. **新增模块**：写 `lib/xxx.sh` → 加入 `MODULES` 索引 → 补 BATS 测试。
4. **目标文件写入**只允许经 `replace_managed_section`，禁止手写 managed 逻辑。
5. 新增功能必须补 BATS 用例；改动后先跑 `make check`。

## 8. 测试约定

- `make test` 通过 `tests/run.sh` **并行**运行各测试文件（默认并发=CPU 核数，`JOBS=N` 可覆盖）；
  每个用例使用唯一的 `$TEST_HOME`（`mktemp -d`）以保证隔离与并行安全
- `tests/helpers/mocks.bash` 把 `HOME` 指到临时目录，并 mock 了
  `curl/git/vim/brew/sudo/node/networksetup/scutil`，测试不得发起真实网络请求或改动真实 `$HOME`
- 测试 setup 将 stdin 重定向到 `/dev/null`，避免从终端运行 `make test` 时继承 tty 而阻塞
- 模块变量（`MANIFEST_FILE`/`CONFIG_FILE`/`SH_CONFIG_FILE` 等）在 setup_mocks 中被 export 覆盖
- 新增测试时遵循现有 `@test` 命名规范（见各 .bats 文件头）

## 9. 一句话风格要求

保持与现有代码一致：中文注释/日志、函数名下划线风格（`_validate_email`）、
常量大写（`EASYWORK_HOME`）、错误信息给出「可复制的修复命令」而非术语。
