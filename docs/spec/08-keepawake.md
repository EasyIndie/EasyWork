# 契约八：设备防休眠 `keepawake`

> 状态：**已实现（Go 引擎 v0.3）**，逻辑冻结待与 §14 一并评审
> 编号：C11（验收点见 §12）｜实现：`internal/keepawake` + `internal/modules/keepawake.go` + `internal/cli/keepawake.go`
> 事实依据：macOS 26/27 两机实测（Intel/OCLP 台式常开 + MacBook Air M1），2026-10。

## 1. 目标与非目标

**目标**：为长跑任务（`ew install`、依赖下载、远程编译、常驻服务）提供**可配置、可诊断、可逆**
的防休眠能力：

- `ew keepawake on` 让设备进入防休眠，`off` 立即失效且重启后不复活；
- `status` 报告**真实断言状态**，而不是"进程还在"的乐观猜测；
- 零 sudo、零新增依赖、不改系统电源策略。

**非目标**：不合盖保活（物理做不到，见 §6）、不做续航优化、不改 `pmset`/`powercfg` 策略。

## 2. 事实基座（实测）

### 2.1 caffeinate 是什么

`/usr/bin/caffeinate` 是**单 Mach-O 二进制**（168 KB，`x86_64 + arm64e`，
`Identifier=com.apple.caffeinate`，`Info.plist=not bound`），只链 CoreFoundation / IOKit /
libSystem，通过 `IOPMAssertionCreateWithName` 向 `powerd` 注册断言。无 app 包、无 GUI、
无后台服务，**SSH 会话里同样生效**。

### 2.2 各 flag 的真实语义

| flag | 断言 | 电池供电时 | 结论 |
|---|---|---|---|
| `-s` | `PreventSystemSleep` | **无效**（对象存在，`Assertion status` 计 0，`powerd` 忽略） | 天生"插电才生效"，拔电自动失效、复电自动恢复 |
| `-i` | `PreventUserIdleSystemSleep` | 有效 | 笔记本上会耗电，仅 `mode=always` 使用 |
| `-d` | `PreventUserIdleDisplaySleep` | 有效 | 仅 `display=true` 使用 |
| `-m` | 磁盘 idle | 有效 | `disksleep=0` 时冗余，**不采用** |
| `-u` | `UserIsActive`（默认 5s） | 有效 | 瞬态，**不采用** |

实测（Air，电池供电下 `caffeinate -s`）：

```
pid 48780(caffeinate): PreventSystemSleep named: "caffeinate command-line tool"   ← 对象在
Assertion status: PreventSystemSleep 0                                          ← 但被判无效
```

### 2.3 两机对照（为何不照搬）

| 项 | 台式常开（Intel/OCLP） | MacBook Air M1 |
|---|---|---|
| `pmset sleep` | AC + 电池都 `0` | AC `0` / 电池 `1` 分钟 |
| 手段 | LaunchAgent `caffeinate -imsu` + `pmset` 硬顶 | 无 |
| 照搬到笔记本的后果 | — | 电池放电至关机；合盖照样睡 |

**三条根据**：① 不使用 `pmset`（需 sudo、升级可能重置、笔电语义错）；② 默认只用 `-s`；
③ `-u`/`-m` 永不使用，`-d` 仅由 `display=true` 触发。

## 3. 能力模型：配置态 vs 运行态

- **配置态（desired）**：`config.toml` 的 `[keepawake]`，持久；
- **运行态（actual）**：持断言的进程 + `$EASYWORK_HOME/run/keepawake.json`，易失。

| 命令 | desired | actual |
|---|---|---|
| `ew keepawake on [flags]` | 写 `enabled=true` + flags 落盘 | 立即起断言（幂等） |
| `ew keepawake off` | 写 `enabled=false` | 停断言 + 拆自启 |
| `ew keepawake status` | 只读回显 | 只读探测（不写盘） |
| `ew install keepawake` | 不变 | 按 config 收敛（`enabled=false` 则停） |
| `ew install keepawake` | 缺省时补写 `enabled=true` | 收敛到 desired |

## 4. 配置契约（`[keepawake]`，仅标量）

```toml
[keepawake]
enabled = "false"   # 是否开启（默认关，符合"人机体验三原则"）
mode    = "ac"      # ac | always；未知值按 ac
display = "false"   # 是否连显示器一起防睡
persist = "false"   # 是否写入开机自启单元
```

`mode=ac` 在 Linux/Windows 无等价断言 → 降级为 `always`，并在 JSON 中
`mode_degraded=true`、日志显式告警，**不得静默**。

## 5. 平台后端

| 平台 | 运行态 | 自启（`persist=true`） | `ac` 语义 |
|---|---|---|---|
| macOS | `/usr/bin/caffeinate` | `~/Library/LaunchAgents/com.easyindie.easywork.keepawake.plist`（`RunAtLoad` + `KeepAlive`） | ✅ 原生 |
| Linux | `systemd-inhibit --what=sleep:idle --who=EasyWork sleep infinity` | `~/.config/systemd/user/easywork-keepawake.service` | ➖ 降级 |
| Windows | `$EASYWORK_HOME/keepawake.ps1`（`powershell -File` 执行，每 30 s 续订 `SetThreadExecutionState(ES_CONTINUOUS\|ES_SYSTEM_REQUIRED[｜ES_DISPLAY_REQUIRED])`） | `$EASYWORK_HOME/keepawake.cmd`（启动器）+ `schtasks /SC ONLOGON` | ➖ 降级 |

**macOS 参数展开（`-d` 在前、`-i` 仅在 always）**：

| mode | display | 参数 |
|---|---|---|
| `ac` | false | `-s` |
| `ac` | true | `-d -s` |
| `always` | false | `-s -i` |
| `always` | true | `-d -s -i` |

缺依赖 → 退出码 `2` + 可复制修复指引（不 fallback 到 `xset` 等不可靠路径）。

## 6. 物理边界（`status`/帮助必须如实说明）

| 触发 | 结果 | 提示 |
|---|---|---|
| 合盖 | 立即睡眠（clamshell 需接电 + 外接屏） | `status` 在 active 时固定提示"请保持开盖" |
| 手动睡眠 / `pmset sleepnow` | 睡眠 | 断言不拦用户主动操作 |
| 电量耗尽 / 过热 | 强制休眠 | — |
| 重启 / 注销 | 断言释放 | 指向 `persist=true` |

### 6.1 `ew doctor` 的电源策略自洽检查

`pmset` 对矛盾组合只会打印 Warning 而**照样写入**，用户很容易"设了以为生效"。
`ew doctor` 因此在 macOS 上增加 `sleep-policy` 检查项（只读，不改系统策略）：

| 判据（`sleep > 0` 时） | 提示 |
|---|---|
| `displaysleep >= sleep` | displaysleep 应小于 sleep（否则熄屏设置不生效） |
| `disksleep == 0` | disksleep 应为非零（sleep 非零时） |

- **AC 与电池两侧都检查**并同时回显（只看当前分支会漏掉另一侧），`sleep=0`（永不）不判为矛盾；
- 非 macOS 平台不输出该项；`--json` 中同样只有 macOS 出现 `sleep-policy`。

## 7. 运行态与幂等

- 状态文件：`$EASYWORK_HOME/run/keepawake.json`
  （`{pid, mode, display, backend, managed_by, started_at, owned_backup}`，原子写）。
- **单实例**：读状态 → 校验身份 → 已生效直接成功。
  身份校验：普通进程要求 `cmdline` 含后端标记（防 pid 复用）；`launchagent`/`systemd`
  以管理器状态为准，并用 `launchctl print`/`systemctl show` **刷新 pid**（KeepAlive 重启后 pid 会变）。
  Windows 用 `tasklist /FI "PID eq N" /FO CSV` 校验映像名（原因见 §7.1）。
- `on` 必须**确认断言已登记**再返回成功（最多等 1 s），失败回滚进程并返回 `1`。
- `off` 无条件成功：`SIGTERM`→`SIGKILL`、清状态、拆自启；未运行时同样返回 `0`。
  自启单元只删除「含 EasyWork 标记」的文件（防止误删同名文件）。
- `uninstall` = `off` + 保留 config；`off` 会把 `enabled` 写回 `false`（避免下次 `install` 又开回来）。

### 7.1 Windows 实现陷阱（真机实测，勿回退）

| 陷阱 | 现象 | 正确做法 |
|---|---|---|
| `DETACHED_PROCESS` 创建进程 | PowerShell **立即 exit 0**，连 `while($true){Start-Sleep}` 都不执行 | 用 `CREATE_NO_WINDOW`(0x08000000)：同样无窗口，但保留控制台子系统 |
| SSH 会话的 Job 对象 | `on` 成功，SSH 断开后进程被杀、`status` 变 `inactive` | 加 `CREATE_BREAKAWAY_FROM_JOB`（不在 Job 中时是 no-op；被拒则退回） |
| 内联 `-Command "<脚本>"` | 脚本里 `[DllImport("kernel32.dll")]` 的双引号被命令行转义改写，进程秒退 | 脚本落盘 `.ps1` + `-File`；`-Filter 'ProcessId=N'` 一律用单引号 |
| session 0 下 WMI | SSH 会话里的进程 `Win32_Process.CommandLine` 可能为 `null`，身份校验恒失败 | 存活判定改用 `tasklist`（映像名），不解析命令行 |
| PowerShell 5.1 读脚本编码 | 无 BOM 的 UTF-8 脚本按 ANSI/GBK 解析，中文注释可破坏语法 | 生成的 `.ps1`/`.cmd` 保持**纯 ASCII** |
| 参数变更被当成幂等 | `on` 后 `on --display` 只改了 config，后端仍无 `ES_DISPLAY_REQUIRED` | 运行中且 `mode`/`display` 变化 ⇒ 重启后端 |
| 改参数反复写单元 | 每次 `ApplyOwnedFile` 备份一次，堆积 `keepawake.ps1.bak.*` | 已含 EasyWork 标记的文件直接覆盖（不备份），`off` 顺手清理历史 `.bak` |

## 8. `status` 五态（防误报）

| 状态 | 判据 |
|---|---|
| `active` | 进程/单元在跑 **且** 断言已登记（macOS 用 `pmset -g assertions` 校验 pid） |
| `pending-ac` | 同上，但 macOS 上当前为电池供电（断言被 `powerd` 忽略） |
| `stale` | 进程在，断言不在（`powerd` 重载、断言被回收） |
| `inactive` | 无状态文件或进程已消失 |
| `unsupported` | 平台无可用后端（如 Linux 缺 `systemd-inhibit`） |

实现陷阱（已踩）：`set -o pipefail` 下 `pmset … | grep -q` 会因 `SIGPIPE`
把"匹配成功"误判为失败 → 一律先捕获输出再用 `strings.Contains`/`case` 匹配。

## 9. CLI 与 JSON

| 命令 | 说明 | 退出码 |
|---|---|---|
| `ew keepawake on [--always\|--ac] [--display] [--persist]` | 写配置并立即生效 | `0`/`1`/`2` |
| `ew keepawake off` | 写 `enabled=false` + 停断言 + 拆自启 | 恒 `0` |
| `ew keepawake status` | 只读探测 | `0` |
| `ew keepawake`（无子命令） | 等价 `status` | `0` |

别名：`awake`、`nosleep`。`--json` 走统一信封，`command` 字段为 `keepawake`。

```jsonc
{ "ok": true, "command": "keepawake", "data": {
    "desired": { "enabled": true, "mode": "ac", "display": false, "persist": true },
    "actual":  { "state": "pending-ac", "pid": 94007, "backend": "caffeinate",
                 "managed_by": "launchagent", "ac_power": false,
                 "assertion": "PreventSystemSleep", "since": "2026-10-23T00:31:12+0800" },
    "mode_degraded": false,
    "platform": "macos" }, "error": null }
```

### 9.1 从「手工方案」迁移

旧方案常见两种组合，迁移时都要显式拆除，否则会与新自启单元并存：

| 旧做法 | 拆除方式 | 注意 |
|---|---|---|
| 手工 LaunchAgent（如 `~/Library/LaunchAgents/keepawake.plist`，`caffeinate -imsu`） | `launchctl bootout gui/$(id -u)/<label>` + 删除 plist（建议先备份到 `$EASYWORK_HOME/legacy/`） | EasyWork 只管自己的 label，不会替你删别人的单元 |
| `sudo pmset -a sleep 0`（AC 与电池都不睡） | 需要时 `sudo pmset -b sleep 10` 收回电池侧；AC 侧可保留 | 该设置与断言互不冲突，但笔记本上会让电池无处释放 |
| `caffeinate` 手工进程（无自启） | `kill <pid>` | 用 `ps -Ao pid,command | grep caffeinate` 找 |

迁移顺序建议：先 `ew keepawake on --persist`（新单元生效），再拆旧单元——中间窗口
最多重叠几秒，不会出现"无人值守"的睡眠空档。

## 10. 为什么不做 `pmset` 方案（决策记录）

| 维度 | `caffeinate`（本契约） | `sudo pmset -a sleep 0`（否） |
|---|---|---|
| sudo | 不需要 | 需要 |
| 系统升级 | 不受影响 | 可能被重置且无提示 |
| 电池语义 | 拔电自动失效 | 电池也不睡，耗到关机 |
| 合盖 | 挡不住 | 也挡不住 |
| 可逆/诊断 | 杀进程即恢复；断言可查 | 需回写参数，易写错 |

`ew doctor` 只**提示**（"确需整机永不休眠请手工执行 `sudo pmset -a sleep 0`"），不自动执行。

## 11. Owned file 写盘原语（已实现）

plist / systemd unit 是整体文件，无法内嵌 managed section 标记。已在 `internal/engine/owned.go`
新增：`ApplyOwnedFile(target, content, perm) (backup, error)`（内容一致即 no-op，接管前备份）
与 `RemoveOwnedFile(target, backup)`（有备份则还原）。是否将其独立为契约九待评审。

## 12. 验收点（C11）与落地情况

| 编号 | 判据 | 位置 |
|---|---|---|
| `C11-status-json-inactive` | 信封字段与 `state=inactive` | `tests/conformance/c11_keepawake.bats` |
| `C11-status-json-has-no-logs-on-stdout` | stdout 纯 JSON、无 ANSI | 同上 |
| `C11-off-idempotent` | 两次 `off` 均 `0`，且 `enabled=false` 落盘 | 同上 |
| `C11-on-dry-run-does-not-start` | `--dry-run` 不写状态 | 同上 |
| `C11-on-rejects-unknown-flag` / `C11-unknown-subcommand` | 退出码 `1` | 同上 |
| `C11-list-marks-optional` / `C11-help-lists-command` | 可选标注 + 帮助 | 同上 |
| 参数展开 / 断言判定 / 五态 / KeepAlive pid 刷新 / owned file | 单测 | `internal/keepawake/*_test.go`、`internal/engine/owned_test.go` |
| Windows 走 `-File` 而非 `-Command`、脚本含标志位 | 单测 | `TestWindowsUsesFileNotCommand` |
| 后端秒退时 `on` 必须失败（不得谎报成功） | 单测 | `TestOnFailsWhenBackendDies` |
| 自启资产（`.ps1`+`.cmd`+schtasks）生成与清理 | 单测 | `TestWindowsPersistAssets` |
| 参数变更重启后端、同参数幂等 | 单测 | `TestOnRestartsWhenSpecChanges` |
| 反复改参数不堆积 `.bak` | 单测 | `TestWriteAssetNoBackupPileUp` |

**真机验证记录（Windows 11 24H2 / PowerShell 5.1 / SSH session 0，2026-10-23）**：

- `on` ⇒ `status=active`、`powercfg /requests` SYSTEM 段出现 `powershell.exe`；
- SSH 断开 3 s 后重连 ⇒ 仍 `active`（breakaway 生效）；
- `kill` 后端 ⇒ `status=inactive`（不谎报）；
- `on --persist --display` ⇒ `.ps1`+`.cmd`+计划任务 `Ready`，脚本标志位 `2147483651`；
- `off` ⇒ 进程 0、文件删除、计划任务消失、无 `.bak` 残留。
- 限制：从 SSH（session 0）观察 `powercfg` 的 DISPLAY 段不可见，`display` 的实际屏幕唤醒需在用户会话（登录任务）中生效。

宿主电源状态在测试中**不得**被真实改动：conformance 只用 `--dry-run` 与只读探测。

## 13. 落地清单（已完成）

| 文件 | 内容 |
|---|---|
| `internal/keepawake/{keepawake,backend}.go` | Spec/State/五态/三平台后端/自启单元 |
| `internal/platform/{proc,proc_unix,proc_windows,power}.go` | pid 存活与身份、脱离会话启动、接电检测 |
| `internal/engine/owned.go` | owned file 原语 |
| `internal/modules/keepawake.go` | 可选模块（`Priority=75`，全平台） |
| `internal/cli/keepawake.go` | `on/off/status` + `--json` |
| `internal/cli/{cli,completion}.go` | 路由、帮助、补全 |
| `internal/engine/config.go` | 默认模板新增 `[keepawake]` |
| `tests/conformance/c11_keepawake.bats`、Go 单测 | 见 §12 |

## 附录：自启单元样例（macOS，实测加载成功）

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.easyindie.easywork.keepawake</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-s</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardErrorPath</key><string>~/.easywork/log/keepawake.log</string>
</dict>
</plist>
```

实测路径：`on --persist` → `launchctl bootstrap` 成功、`launchctl print` 显示
`state = running` / `pid = …`；`kill -9` 后 2 s 内被 KeepAlive 拉起（pid 变化，`status` 仍 `active`）；
`off` 后 plist 删除、`launchctl print` 报 "Could not find service"、无残留 caffeinate 进程。
