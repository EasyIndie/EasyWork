package keepawake

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// fakeRunner 记录调用并模拟进程存活。
type fakeRunner struct {
	started  []string
	run      map[string]string // "cmd args..." -> stdout
	killed   []int
	alive    map[int]bool
	cmdlines map[int]string
	startPID int
}

func newFakeRunner() *fakeRunner {
	return &fakeRunner{run: map[string]string{}, alive: map[int]bool{}, cmdlines: map[int]string{}, startPID: 4242}
}

func key(name string, args []string) string { return name + " " + strings.Join(args, " ") }

func (f *fakeRunner) Run(name string, args ...string) (string, error) {
	f.started = append(f.started, key(name, args))
	return f.run[key(name, args)], nil
}

func (f *fakeRunner) Start(name string, args ...string) (int, error) {
	f.started = append(f.started, key(name, args))
	f.alive[f.startPID] = true
	return f.startPID, nil
}

func (f *fakeRunner) Kill(pid int) error {
	f.killed = append(f.killed, pid)
	f.alive[pid] = false
	return nil
}

func (f *fakeRunner) Cmdline(pid int) (string, bool) {
	if !f.alive[pid] {
		return "", false
	}
	if c, ok := f.cmdlines[pid]; ok {
		return c, true
	}
	return "systemd-inhibit --what=sleep:idle sleep infinity", true
}

func newTestController(t *testing.T, osName platform.OS) (*Controller, *fakeRunner) {
	t.Helper()
	dir := t.TempDir()
	env := platform.Env{Home: dir, EasyworkHome: filepath.Join(dir, ".easywork"), TempDir: dir}
	r := newFakeRunner()
	log := logx.New()
	r.cmdlines[r.startPID] = "systemd-inhibit --what=sleep:idle sleep infinity"
	if osName == platform.Windows {
		r.cmdlines[r.startPID] = `powershell -NoProfile -File C:\Users\x\.easywork\keepawake.ps1`
	}
	ctl := &Controller{Env: env, Log: log, OS: osName, Run: r,
		Available: func(platform.OS) bool { return true },
		PowerAC:   func() bool { return true },
		ProcMatch: func(pid int, image string) bool {
			_, ok := r.cmdlines[pid]
			return r.alive[pid] && ok
		}}
	return ctl, r
}

func TestSpecNormalizedAndEffective(t *testing.T) {
	if got := (Spec{Mode: "bogus"}).Normalized().Mode; got != ModeAC {
		t.Fatalf("非法 mode 应回落 ac，得到 %q", got)
	}
	// macOS 保持 ac；其他平台降级为 always 并标记
	if eff, degraded := (Spec{Mode: ModeAC}).Effective(platform.MacOS); eff.Mode != ModeAC || degraded {
		t.Fatalf("macOS 应保持 ac，得到 %v degraded=%v", eff.Mode, degraded)
	}
	for _, osName := range []platform.OS{platform.Linux, platform.Windows} {
		if eff, degraded := (Spec{Mode: ModeAC}).Effective(osName); eff.Mode != ModeAlways || !degraded {
			t.Fatalf("%s 应降级为 always，得到 %v degraded=%v", osName, eff.Mode, degraded)
		}
	}
	if _, degraded := (Spec{Mode: ModeAlways}).Effective(platform.Linux); degraded {
		t.Fatal("always 不应标记降级")
	}
}

func TestBackendForMacOSArgs(t *testing.T) {
	cases := []struct {
		spec Spec
		want string
	}{
		{Spec{Mode: ModeAC}, "-s"},
		{Spec{Mode: ModeAC, Display: true}, "-d -s"},
		{Spec{Mode: ModeAlways}, "-s -i"},
		{Spec{Mode: ModeAlways, Display: true}, "-d -s -i"},
	}
	for _, c := range cases {
		call := backendFor(platform.Env{}, c.spec, platform.MacOS)
		if call.Name != "/usr/bin/caffeinate" {
			t.Fatalf("macOS 后端应为 /usr/bin/caffeinate，得到 %s", call.Name)
		}
		if got := strings.Join(call.Args, " "); got != c.want {
			t.Fatalf("%+v 参数应为 %q，得到 %q", c.spec, c.want, got)
		}
	}
}

func TestLaunchAgentPlistContent(t *testing.T) {
	env := platform.Env{Home: "/tmp/h", EasyworkHome: "/tmp/h/.easywork"}
	plist := launchAgentPlist(env, backendFor(env, Spec{Mode: ModeAlways, Display: true}, platform.MacOS))
	for _, want := range []string{
		"<string>" + Label + "</string>",
		"<string>/usr/bin/caffeinate</string>",
		"<string>-d</string>", "<string>-s</string>", "<string>-i</string>",
		"<key>RunAtLoad</key><true/>", "<key>KeepAlive</key><true/>",
	} {
		if !strings.Contains(plist, want) {
			t.Fatalf("plist 缺少 %q：\n%s", want, plist)
		}
	}
}

func TestSystemdUnitText(t *testing.T) {
	unit := systemdUnitText(backendFor(platform.Env{}, Spec{Mode: ModeAlways}, platform.Linux))
	if !strings.Contains(unit, "ExecStart=") || !strings.Contains(unit, "systemd-inhibit") {
		t.Fatalf("systemd 单元缺少 ExecStart/后端：\n%s", unit)
	}
	if !strings.Contains(unit, "--what=sleep:idle") {
		t.Fatalf("systemd 单元应阻止 sleep/idle：\n%s", unit)
	}
}

func TestWindowsScriptFlags(t *testing.T) {
	if !strings.Contains(windowsScript(false), "2147483649") {
		t.Fatal("默认应为 ES_CONTINUOUS|ES_SYSTEM_REQUIRED")
	}
	if !strings.Contains(windowsScript(true), "2147483651") {
		t.Fatal("display=true 应追加 ES_DISPLAY_REQUIRED")
	}
}

func TestParseLaunchctlPID(t *testing.T) {
	out := "gui/501/com.easyindie.easywork.keepawake = {\n\tactive count = 1\n\tpid = 94007\n}\n"
	if got := parseLaunchctlPID(out); got != 94007 {
		t.Fatalf("应解析出 94007，得到 %d", got)
	}
	if got := parseLaunchctlPID("state = running"); got != 0 {
		t.Fatalf("无 pid 行应返回 0，得到 %d", got)
	}
}

func TestOnOffCycleLinux(t *testing.T) {
	ctl, r := newTestController(t, platform.Linux)
	spec := Spec{Enabled: true, Mode: ModeAC} // 在 Linux 上应降级为 always

	if err := ctl.On(spec); err != nil {
		t.Fatalf("On 失败: %v", err)
	}
	st, ok := ctl.loadState()
	if !ok || st.PID != 4242 || st.ManagedBy != "process" {
		t.Fatalf("状态文件不正确: %+v ok=%v", st, ok)
	}
	if st.Mode != string(ModeAlways) {
		t.Fatalf("Linux 上应记录降级后的 always，得到 %q", st.Mode)
	}
	if !strings.Contains(strings.Join(r.started, "|"), "systemd-inhibit") {
		t.Fatalf("应启动 systemd-inhibit，实际调用: %v", r.started)
	}

	// 幂等：再次 On 不应重复启动
	before := len(r.started)
	if err := ctl.On(spec); err != nil {
		t.Fatalf("幂等 On 失败: %v", err)
	}
	if len(r.started) != before {
		t.Fatalf("幂等 On 不应重复启动: %v", r.started[before:])
	}

	if err := ctl.Off(); err != nil {
		t.Fatalf("Off 失败: %v", err)
	}
	if _, ok := ctl.loadState(); ok {
		t.Fatal("Off 后应清除状态文件")
	}
	if len(r.killed) != 1 || r.killed[0] != 4242 {
		t.Fatalf("Off 应终止 pid 4242，得到 %v", r.killed)
	}
	// 幂等：未运行时 Off 仍返回 nil
	if err := ctl.Off(); err != nil {
		t.Fatalf("幂等 Off 失败: %v", err)
	}
}

func TestStatusStates(t *testing.T) {
	ctl, r := newTestController(t, platform.Linux)
	spec := Spec{Enabled: true, Mode: ModeAC}

	// 无状态文件 → inactive
	if got := ctl.Status(spec).Actual.State; got != StateInactive {
		t.Fatalf("应为 inactive，得到 %s", got)
	}

	// 进程在、断言缺失（Linux 以存活为准，故模拟 pid 不可读）→ inactive
	if err := ctl.On(spec); err != nil {
		t.Fatalf("On 失败: %v", err)
	}
	if got := ctl.Status(spec).Actual.State; got != StateActive {
		t.Fatalf("应为 active，得到 %s", got)
	}

	// 断言丢失：macOS 分支下 pid 在但 pmset 无记录 → stale
	r.run[key("pmset", []string{"-g", "assertions"})] = ""
	macCtl, macRunner := newTestController(t, platform.MacOS)
	macRunner.alive[4242] = true
	macRunner.cmdlines[4242] = "/usr/bin/caffeinate -s"
	if err := macCtl.saveState(State{PID: 4242, Mode: "ac", Backend: "caffeinate", ManagedBy: "process"}); err != nil {
		t.Fatal(err)
	}
	if got := macCtl.Status(spec).Actual.State; got != StateStale {
		t.Fatalf("无断言应为 stale，得到 %s", got)
	}

	// 断言存在 + 电池供电 → pending-ac
	macRunner.run[key("pmset", []string{"-g", "assertions"})] = "pid 4242(caffeinate): PreventSystemSleep"
	macCtl.PowerAC = func() bool { return false }
	if got := macCtl.Status(spec).Actual.State; got != StatePendingAC {
		t.Fatalf("电池供电应为 pending-ac，得到 %s", got)
	}

	// 断言存在 + 接电 → active
	macCtl.PowerAC = func() bool { return true }
	st := macCtl.Status(spec)
	if st.Actual.State != StateActive || st.Actual.Assertion != "PreventSystemSleep" {
		t.Fatalf("接电应为 active 且带断言名，得到 %+v", st.Actual)
	}

	// 后端不可用 → unsupported
	macCtl.Available = func(platform.OS) bool { return false }
	if got := macCtl.Status(spec).Actual.State; got != StateUnsupported {
		t.Fatalf("后端缺失应为 unsupported，得到 %s", got)
	}
}

func TestOffRemovesOwnedUnit(t *testing.T) {
	ctl, r := newTestController(t, platform.MacOS)
	uf := unitFileFor(ctl.Env, Spec{Mode: ModeAC}, platform.MacOS)
	if err := os.MkdirAll(filepath.Dir(uf.Path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(uf.Path, []byte(uf.Content), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := ctl.Off(); err != nil {
		t.Fatalf("Off 失败: %v", err)
	}
	if _, err := os.Stat(uf.Path); !os.IsNotExist(err) {
		t.Fatal("Off 应移除自启单元")
	}
	if !strings.Contains(strings.Join(r.started, "|"), "launchctl bootout") {
		t.Fatalf("应 bootout LaunchAgent，实际: %v", r.started)
	}
}

func TestOffKeepsForeignUnit(t *testing.T) {
	ctl, _ := newTestController(t, platform.MacOS)
	uf := unitFileFor(ctl.Env, Spec{Mode: ModeAC}, platform.MacOS)
	if err := os.MkdirAll(filepath.Dir(uf.Path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(uf.Path, []byte("<plist>别人的文件</plist>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := ctl.Off(); err != nil {
		t.Fatalf("Off 失败: %v", err)
	}
	if _, err := os.Stat(uf.Path); err != nil {
		t.Fatal("非 EasyWork 生成的文件不得删除")
	}
}

func TestDryRunTouchesNothing(t *testing.T) {
	ctl, r := newTestController(t, platform.Linux)
	ctl.DryRun = true
	if err := ctl.On(Spec{Enabled: true, Mode: ModeAlways}); err != nil {
		t.Fatalf("dry-run On 失败: %v", err)
	}
	if len(r.started) != 0 {
		t.Fatalf("dry-run 不应执行命令: %v", r.started)
	}
	if _, ok := ctl.loadState(); ok {
		t.Fatal("dry-run 不应写状态文件")
	}
}

// KeepAlive 重启后 pid 变化：状态仍应为 active（pid 由管理器刷新）。
func TestStatusLaunchAgentPidChanges(t *testing.T) {
	ctl, r := newTestController(t, platform.MacOS)
	spec := Spec{Enabled: true, Mode: ModeAC, Persist: true}
	if err := ctl.saveState(State{PID: 111, Mode: "ac", Backend: "caffeinate", ManagedBy: "launchagent"}); err != nil {
		t.Fatal(err)
	}
	r.run[key("launchctl", []string{"print", launchctlDomain() + "/" + Label})] =
		"\tstate = running\n\tpid = 222\n"
	r.run[key("pmset", []string{"-g", "assertions"})] = "pid 222(caffeinate): PreventSystemSleep"

	st := ctl.Status(spec)
	if st.Actual.State != StateActive {
		t.Fatalf("应为 active，得到 %+v", st.Actual)
	}
	if st.Actual.PID != 222 {
		t.Fatalf("pid 应刷新为 222，得到 %d", st.Actual.PID)
	}

	// 单元停止 → inactive（即便状态文件仍在）
	r.run[key("launchctl", []string{"print", launchctlDomain() + "/" + Label})] = "\tstate = exited\n"
	if got := ctl.Status(spec).Actual.State; got != StateInactive {
		t.Fatalf("单元停止应为 inactive，得到 %s", got)
	}
}

// Windows 必须走 -File（内联 -Command 会因 DllImport 的双引号秒退），且 start 前脚本已落盘。
func TestWindowsUsesFileNotCommand(t *testing.T) {
	ctl, r := newTestController(t, platform.Windows)
	spec := Spec{Enabled: true, Mode: ModeAC}
	if err := ctl.On(spec); err != nil {
		t.Fatalf("On 失败: %v", err)
	}
	call := strings.Join(r.started, "|")
	if strings.Contains(call, "-Command") {
		t.Fatalf("不得使用内联 -Command: %v", r.started)
	}
	if !strings.Contains(call, "-File") || !strings.Contains(call, "keepawake.ps1") {
		t.Fatalf("应以 -File 执行脚本: %v", r.started)
	}
	script := filepath.Join(ctl.Env.EasyworkHome, "keepawake.ps1")
	data, err := os.ReadFile(script)
	if err != nil {
		t.Fatalf("脚本未落盘: %v", err)
	}
	for _, want := range []string{"SetThreadExecutionState", "EasyWork keepawake", "2147483649"} {
		if !strings.Contains(string(data), want) {
			t.Fatalf("脚本缺少 %q:\n%s", want, data)
		}
	}
	// Off 必须连脚本一起清掉
	if err := ctl.Off(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(script); !os.IsNotExist(err) {
		t.Fatal("Off 应删除常驻脚本")
	}
}

// 后端启动后秒退（如 Add-Type 失败）→ On 必须失败，不得报成功。
func TestOnFailsWhenBackendDies(t *testing.T) {
	ctl, r := newTestController(t, platform.Windows)
	r.startPID = 777
	// Start 返回 pid 但进程立刻消失（cmdline 不可读）
	r.alive[777] = false
	err := ctl.On(Spec{Enabled: true, Mode: ModeAlways})
	if err == nil {
		t.Fatal("后端秒退时 On 必须返回错误")
	}
	if !strings.Contains(err.Error(), "断言未注册") {
		t.Fatalf("错误信息应说明断言未注册，得到: %v", err)
	}
	if _, ok := ctl.loadState(); ok {
		t.Fatal("失败时不得留下状态文件")
	}
}

// 自启：启动器 .cmd 指向 .ps1，schtasks 注册，off 时两者都清。
func TestWindowsPersistAssets(t *testing.T) {
	ctl, r := newTestController(t, platform.Windows)
	spec := Spec{Enabled: true, Mode: ModeAlways, Display: true, Persist: true}
	if err := ctl.On(spec); err != nil {
		t.Fatalf("On --persist 失败: %v", err)
	}
	launcher := filepath.Join(ctl.Env.EasyworkHome, "keepawake.cmd")
	script := filepath.Join(ctl.Env.EasyworkHome, "keepawake.ps1")
	for _, f := range []string{launcher, script} {
		if _, err := os.Stat(f); err != nil {
			t.Fatalf("%s 未生成: %v", f, err)
		}
	}
	cmd, _ := os.ReadFile(launcher)
	if !strings.Contains(string(cmd), "-File") || !strings.Contains(string(cmd), "keepawake.ps1") {
		t.Fatalf("启动器应调用 -File 脚本:\n%s", cmd)
	}
	if !strings.Contains(strings.Join(r.started, "|"), "schtasks /Create") {
		t.Fatalf("应注册计划任务: %v", r.started)
	}
	if err := ctl.Off(); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{launcher, script} {
		if _, err := os.Stat(f); !os.IsNotExist(err) {
			t.Fatalf("Off 后 %s 应被删除", f)
		}
	}
	if !strings.Contains(strings.Join(r.started, "|"), "schtasks /Delete") {
		t.Fatalf("应删除计划任务: %v", r.started)
	}
}

// 参数变化（display 开关）必须重启后端，而不是误判为幂等。
func TestOnRestartsWhenSpecChanges(t *testing.T) {
	ctl, r := newTestController(t, platform.Linux)
	if err := ctl.On(Spec{Enabled: true, Mode: ModeAlways, Display: false}); err != nil {
		t.Fatal(err)
	}
	first, _ := ctl.loadState()
	if err := ctl.On(Spec{Enabled: true, Mode: ModeAlways, Display: true}); err != nil {
		t.Fatalf("参数变更后 On 失败: %v", err)
	}
	second, _ := ctl.loadState()
	if !second.Display {
		t.Fatal("新状态应记录 display=true")
	}
	if len(r.killed) != 1 || r.killed[0] != first.PID {
		t.Fatalf("应终止旧进程 %d，得到 %v", first.PID, r.killed)
	}
	// 参数未变时仍是幂等
	before := len(r.started)
	if err := ctl.On(Spec{Enabled: true, Mode: ModeAlways, Display: true}); err != nil {
		t.Fatal(err)
	}
	if len(r.started) != before {
		t.Fatal("参数未变时不应重启")
	}
}

// 同一文件反复写入（改参数）不得堆积 .bak 备份。
func TestWriteAssetNoBackupPileUp(t *testing.T) {
	ctl, _ := newTestController(t, platform.Windows)
	path := windowsScriptPath(ctl.Env)
	if _, err := ctl.writeAsset(path, windowsScript(false)); err != nil {
		t.Fatal(err)
	}
	// 改成 display=true（内容变化，但文件已属 EasyWork）
	if _, err := ctl.writeAsset(path, windowsScript(true)); err != nil {
		t.Fatal(err)
	}
	matches, err := filepath.Glob(filepath.Join(ctl.Env.EasyworkHome, "keepawake.*.bak.*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("不应产生备份文件: %v", matches)
	}
	// 但接管别人的文件仍要备份
	foreign := filepath.Join(ctl.Env.EasyworkHome, "user-file.plist")
	if err := os.WriteFile(foreign, []byte("<plist>mine</plist>"), 0o644); err != nil {
		t.Fatal(err)
	}
	backup, err := ctl.writeAsset(foreign, "EasyWork content")
	if err != nil {
		t.Fatal(err)
	}
	if backup == "" {
		t.Fatal("接管外部文件必须备份")
	}
}
