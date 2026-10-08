# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与
[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-10-08

v2 改造：从「交互式安装向导」升级为「**声明式配置 + 幂等执行引擎 + 人机/AI 双受众**」。

### 新增

- **命令 `ew`**：短命令（`easywork` 保留为软链别名），shell 补全同时覆盖两者
- **`init` 命令**：零交互轻量初始化（Shell 别名 + Git 别名，零重依赖）
- **`status` / `doctor` / `list` 命令**：状态总览、环境诊断、组件列表
- **`--json` 输出**：`version`/`status`/`list`/`doctor` 统一信封，含结构化 `update` 字段
- **`--offline`**：禁止联网（跳过下载/安装）
- **`config.toml`**：声明式配置；`config get/set`；旧 ini 自动迁移
- **`gh` 模块**：自动安装 GitHub CLI；旧发行版（apt/dnf/yum 默认源缺失）自动添加官方源
- **`ai-tools` 模块**：自动安装 claude code / codex / pi（经 npm；可经配置关闭）
- **升级提示**：安装 / 状态时提示新版本（非阻塞、24h 节流、`--offline`/`--json` 自动跳过）

### 变更

- 新增**模块引擎**（`apply_managed_file` 等），模块声明化，消除重复样板
- Shell 模块**分层**：花哨提示符 / Oh My Zsh / 网络工具默认关闭
- Git 身份**自动探测**，缺失时仍安装别名、不阻塞
- `manifest` 增加 `schema_version`；统一状态根 `EASYWORK_HOME`（可覆盖）
- 卸载时可还原用户原配置备份

### 修复

- 从交互式终端运行测试阻塞（`cmd_update` 的 `read` 等待 tty）
- 框架覆盖模块写入的 manifest 键（导致卸载无法还原备份）
- 测试隔离 `EASYWORK_*` 环境变量泄漏导致的误报

### 文档

- 新增 `AGENTS.md`（AI 协作指引）、`DESIGN.md`（v2 蓝图）
- README 增补 `--json` 示例、模块说明、跨平台支持

## [0.0.1] - 2026-06-13

首个公开版本。

- `shell` / `git` / `vim` 三个模块
- 模块自动发现、幂等 managed section、备份/还原、manifest 状态追踪
- `curl | bash` 一键安装、`install` / `uninstall` / `config` / `version` / `update` / `completion`
