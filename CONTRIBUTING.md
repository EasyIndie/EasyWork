# 贡献指南

感谢你考虑为 EasyWork 贡献代码！

## 提 Issue

- 使用 GitHub Issues 提交 bug 报告或功能请求
- 请尽可能详细描述：复现步骤、期望行为、实际行为（`ew version`、OS/架构、`--json` 输出）
- 如果涉及报错，请附上完整的错误输出

## 提 Pull Request

1. Fork 本仓库
2. 创建特性分支：
   ```bash
   git checkout -b feature/my-feature
   ```
3. 开发并确保质量通过：
   ```bash
   make check   # ShellCheck + shfmt + go test + conformance + 安装链路
   ```
4. 提交 PR 到 `main` 分支

## 开发环境

### 前置条件

- **Go 1.22+**（CI 用 1.24）
- **ShellCheck** — 引导/辅助脚本静态分析
- **shfmt** — shell 脚本格式化
- **BATS** — 黑盒 conformance 测试框架

```bash
# macOS
brew install go shellcheck shfmt bats-core

# Ubuntu/Debian
sudo apt-get install -y golang shellcheck shfmt
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
sudo /tmp/bats/install.sh /usr/local
```

### 常用命令

| 命令 | 说明 |
|---|---|
| `make build` | 构建到 `.build/ew` |
| `make gotest` | Go 单元测试 |
| `make test` | 黑盒 conformance（`tests/conformance`，只测 Go） |
| `make lint` / `make fmt` / `make fmt-check` | shell 脚本检查与格式化 |
| `make check` | 完整质量检查（含安装链路 e2e） |
| `make install-e2e` | bootstrap + update 本地镜像端到端（不触网） |
| `make acceptance` | 一键验收（含交叉编译、退役不变量） |
| `make retire-check` | 断言 Bash 引擎没有复活 |

### 本机测试

```bash
make build
./.build/ew status            # 只读
./.build/ew install --dry-run # 预览变更

# 完整安装（注意会修改本机配置）
make install && ew install --yes

# 防休眠（可选，需要时再开）
./.build/ew keepawake on && ./.build/ew keepawake status
```

## 编码规范（Go）

- **平台差异**集中在 `internal/platform`，业务代码不散落 `runtime.GOOS` 分支
- **可测试性**：外部命令/电源/时间等副作用通过注入（`Runner` 等）隔离，
  单测不得改动宿主真实状态
- **错误信息**给出「可复制的修复命令」，而非术语
- **JSON/日志分流**：数据走 stdout、日志走 stderr；`--json` 的字节格式是契约
- **文档**：改行为先改 `docs/spec/`；模块新增请同时补 `*_test.go`

## 编码规范（Shell）

仓库内 shell 仅剩引导/安装/验收脚本（`bootstrap.sh`、`scripts/*.sh`）：

- 必须通过 ShellCheck 与 `shfmt -i 4 -bn -ci -sr`
- 兼容 bash 3.2（macOS 自带）与 zsh 语法检查
- **不要恢复** Bash 引擎（`make retire-check` 会拦）

## 许可证

贡献即表示你同意你的代码在 [MIT](LICENSE) 许可下发布。
