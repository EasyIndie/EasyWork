# 迭代流程（单次快速迭代）

> 目标：**改一行代码到拿到 CI 结论 ≤ 2 分钟**；重矩阵只在必要的时候跑一次。
> 规范契约见 `docs/spec/`，验收映射见 `docs/ACCEPTANCE.md`。

## 1. 分层门禁

| 层 | 触发 | 内容 | 耗时 |
|---|---|---|---|
| 本地 `make quick` | 手工 | shfmt 检查 + `go test` + conformance | < 1 分钟 |
| `quick` 任务 | 每次 push / PR | 同上（+ ShellCheck / `bash -n` / `gofmt` / `go vet`） | ~1–2 分钟 |
| 重矩阵 | **仅 main 推送**、确有代码改动、`quick` 已过 | macOS ShellCheck、macOS/Windows conformance + 原生冒烟、三平台安装链路 e2e、6 目标交叉编译 | 10–20 分钟 |
| `Pages` | 仅 `site/**` 改动 | 静态页直接部署 | ~20 秒 |
| `Release` | 打 tag `x.y.z` | 6 目标二进制 + `checksums.txt` + provenance | ~2 分钟 |

关键设计：

- **PR 只跑快车道**：PR 上不跑 macOS/Windows 矩阵，反馈 ≤ 2 分钟；全量在合并到 `main` 后跑。
- **纯文档/站点改动自动降级**：`docs/**`、`site/**`、`*.md`、`LICENSE` 之外没有改动时，
  重矩阵整体跳过（`Changed paths` 任务判定）。
- **同分支并发取消**：`concurrency.cancel-in-progress`，新提交立刻顶掉还在跑的旧运行，
  不会排队等 15 分钟。
- **失败即止**：重矩阵 `needs: quick`，快车道红灯时不会浪费 Windows/macOS 机时。

## 2. 单次快速迭代（日常）

```bash
git switch -c fix/doctor-sleep-policy   # 分支：feat/ fix/ docs/ ci/ chore/
# …改代码…
make quick                              # < 1 分钟，红了先修好再推
git commit -m 'fix(doctor): …'          # 见 §3 提交规范
git push -u origin HEAD                 # 或直接 gh pr create
gh pr create --fill                     # PR 自动跑 quick（~2 分钟）
gh pr checks --watch                    # 绿灯即可合并
```

合并到 `main` 后自动跑重矩阵；若只改文档/站点，重矩阵会被跳过。

**只想跑一次快车道**（不验证平台矩阵）：

```bash
gh workflow run ci.yml -f scope=fast && gh run watch
```

## 3. 提交与分支规范

提交信息：`type(scope): 中文摘要`，type 取 `feat|fix|docs|refactor|test|chore|ci|perf|polish`。

- 摘要一句话说清「改了什么、为什么」，不加句号；
- 行为变化必须在正文写**验证方式**（跑了哪个命令 / 哪个用例）；
- 一个提交只做一件事；格式化与逻辑修改分开提交，方便 review 与回滚；
- 分支短生命周期，合并后删除。

## 4. 改动落到哪一层

| 改动 | 必做 |
|---|---|
| 行为/契约（CLI、JSON、模块、keepawake…） | 先改 `docs/spec/`，再改实现，补 `*_test.go` **和** `tests/conformance/*.bats` |
| 新增模块 | `internal/modules/xxx.go` → `registry`（字母序）→ 单测 → conformance |
| 引导/安装脚本 | ShellCheck + `shfmt -d` + `make install-e2e` |
| 环境相关诊断（`pmset`、`powercfg`…） | conformance 必须注入假命令固定输出，**不得**依赖宿主真实状态 |
| 仅文档/站点 | `make quick` 足以；`site/**` 会自动部署 Pages |

> 「环境相关诊断」这条是踩过坑的：`sleep-policy` 用例原先直接读宿主 `pmset`，
> GitHub macOS 虚拟机只有 AC 分支 → CI 长期红灯（0.4.4 已修，见 CHANGELOG）。

## 5. 发布

1. `internal/version/version.go` 改 `Version`（唯一版本来源）+ CHANGELOG 增加版本段；
2. 提交 `chore(release): x.y.z（一句话）`；
3. `git tag x.y.z && git push origin x.y.z` → `Release` 工作流产出 6 目标二进制；
4. 发布会校验 tag 与 `version.go` 一致，不一致直接失败。
