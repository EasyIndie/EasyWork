package keepawake

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// 运行态状态取值（封闭集合，见 docs/spec/08-keepawake.md §8）。
const (
	StateActive      = "active"
	StatePendingAC   = "pending-ac"
	StateInactive    = "inactive"
	StateStale       = "stale"
	StateUnsupported = "unsupported"
)

// ErrUnsupported 表示当前平台没有可用的防休眠后端（退出码 2）。
var ErrUnsupported = errors.New("当前平台不支持设备防休眠")

// ErrUnavailable 表示后端依赖缺失（退出码 2）。
var ErrUnavailable = errors.New("缺少防休眠依赖")

// State 是落盘的运行态（$EASYWORK_HOME/run/keepawake.json）。
type State struct {
	PID       int    `json:"pid"`
	Mode      string `json:"mode"`
	Display   bool   `json:"display"`
	Backend   string `json:"backend"`
	ManagedBy string `json:"managed_by"`
	StartedAt string `json:"started_at"`
	Backup    string `json:"owned_backup,omitempty"`
}

// Actual 是探测到的真实状态。
type Actual struct {
	State     string `json:"state"`
	PID       int    `json:"pid,omitempty"`
	Backend   string `json:"backend,omitempty"`
	ManagedBy string `json:"managed_by,omitempty"`
	ACPower   *bool  `json:"ac_power,omitempty"`
	Assertion string `json:"assertion,omitempty"`
	Since     string `json:"since,omitempty"`
}

// Status 是 `ew keepawake status` 的完整结果。
type Status struct {
	Desired      Spec   `json:"desired"`
	Actual       Actual `json:"actual"`
	ModeDegraded bool   `json:"mode_degraded"`
	Platform     string `json:"platform"`
}

// Runner 抽象外部命令调用（便于测试注入）。
type Runner interface {
	Run(name string, args ...string) (string, error)
	Start(name string, args ...string) (int, error)
	Kill(pid int) error
	Cmdline(pid int) (string, bool)
}

type execRunner struct{}

func (execRunner) Run(name string, args ...string) (string, error) {
	out, err := execOutput(name, args...)
	return out, err
}

func (execRunner) Start(name string, args ...string) (int, error) {
	return platform.StartDetached(name, args...)
}

func (execRunner) Kill(pid int) error { return platform.KillProcess(pid) }

func (execRunner) Cmdline(pid int) (string, bool) { return platform.ProcessCmdline(pid) }

// Controller 负责防休眠的启停与探测。
type Controller struct {
	Env    platform.Env
	Log    *logx.Logger
	DryRun bool
	OS     platform.OS
	Run    Runner

	// Available/PowerAC/ProcMatch 是注入点（测试用）；为 nil 时使用真实探测。
	Available func(platform.OS) bool
	PowerAC   func() bool
	ProcMatch func(pid int, image string) bool
}

// NewController 返回使用真实环境的控制器。
func NewController(env platform.Env, log *logx.Logger, dryRun bool) *Controller {
	return &Controller{Env: env, Log: log, DryRun: dryRun, OS: platform.DetectOS(), Run: execRunner{},
		Available: backendAvailable, PowerAC: platform.OnAC, ProcMatch: platform.ProcessMatches}
}

// available 报告后端是否可用（可注入）。
func (c *Controller) available() bool {
	if c.Available != nil {
		return c.Available(c.OS)
	}
	return backendAvailable(c.OS)
}

// powerAC 报告是否接电（可注入）。
func (c *Controller) powerAC() bool {
	if c.PowerAC != nil {
		return c.PowerAC()
	}
	return platform.OnAC()
}

// 状态文件路径。
func (c *Controller) statePath() string {
	return filepath.Join(c.Env.EasyworkHome, "run", "keepawake.json")
}

func (c *Controller) loadState() (State, bool) {
	var st State
	data, err := os.ReadFile(c.statePath())
	if err != nil {
		return st, false
	}
	if err := json.Unmarshal(data, &st); err != nil {
		return State{}, false
	}
	return st, st.Backend != ""
}

func (c *Controller) saveState(st State) error {
	data, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return err
	}
	return platform.AtomicWrite(c.statePath(), append(data, '\n'), 0o644)
}

func (c *Controller) clearState() { _ = os.Remove(c.statePath()) }

// refreshPID 从自启管理器取当前 pid（KeepAlive 重启后 pid 会变）。
func (c *Controller) refreshPID(st State) State {
	switch st.ManagedBy {
	case "launchagent":
		if out, err := c.Run.Run("launchctl", "print", launchctlDomain()+"/"+Label); err == nil {
			if pid := parseLaunchctlPID(out); pid > 0 {
				st.PID = pid
			}
		}
	case "systemd":
		if pid := c.systemdMainPID(); pid > 0 {
			st.PID = pid
		}
	}
	return st
}

// alive 判定进程/单元是否在跑：自启单元以管理器状态为准，普通进程校验命令行
// 身份（防 pid 复用误判）。
func (c *Controller) alive(st State) bool {
	switch st.ManagedBy {
	case "launchagent":
		out, err := c.Run.Run("launchctl", "print", launchctlDomain()+"/"+Label)
		return err == nil && strings.Contains(out, "state = running")
	case "systemd":
		out, err := c.Run.Run("systemctl", "--user", "is-active", SystemdUnit)
		return err == nil && strings.TrimSpace(out) == "active"
	}
	if st.PID <= 0 {
		return false
	}
	call := backendFor(c.Env, c.effective(st), c.OS)
	if c.OS == platform.Windows {
		// 以映像名判定（powershell.exe 的完整命令行在 session 0 下取不到）
		match := c.ProcMatch
		if match == nil {
			match = platform.ProcessMatches
		}
		return match(st.PID, "powershell.exe")
	}
	cmdline, ok := c.Run.Cmdline(st.PID)
	if !ok {
		return false
	}
	return strings.Contains(cmdline, call.Marker)
}

// effective 由落盘状态还原 spec（探测时只需其中影响命令行的字段）。
func (c *Controller) effective(st State) Spec {
	return Spec{Enabled: true, Mode: Mode(st.Mode), Display: st.Display}
}

// assertionHeld 报告断言是否真的被系统接纳（不只是进程还活着）。
// macOS 用 pmset 检查；其余平台以进程存活为准。
func (c *Controller) assertionHeld(st State) bool {
	if c.OS != platform.MacOS {
		// 无 pmset 可查：以「进程仍在」作为断言存在的判据。
		// 不能无条件返回 true —— 后端秒退时会把失败误报为成功。
		return c.alive(st)
	}
	if st.PID <= 0 {
		return true // LaunchAgent 进程由 launchd 持有，alive 已判定 running
	}
	out, err := c.Run.Run("pmset", "-g", "assertions")
	if err != nil {
		return false
	}
	return strings.Contains(out, fmt.Sprintf("pid %d(caffeinate)", st.PID))
}

// assertionName 返回探测到的断言名（人类输出用）。
func assertionName(osName platform.OS) string {
	if osName == platform.MacOS {
		return "PreventSystemSleep"
	}
	return ""
}

// SpecFromConfig 从 config.toml 读取 [keepawake] 段。
func SpecFromConfig(c engine.Config) Spec {
	spec := Spec{
		Enabled: c.GetBool("keepawake.enabled", false),
		Mode:    Mode(c.Get("keepawake.mode", string(ModeAC))),
		Display: c.GetBool("keepawake.display", false),
		Persist: c.GetBool("keepawake.persist", false),
	}
	return spec.Normalized()
}

// ─── 启停 ─────────────────────────────────────────────────────

// On 启动防休眠（幂等）。已生效时直接返回 nil。
func (c *Controller) On(spec Spec) error {
	spec = spec.Normalized()
	eff, degraded := spec.Effective(c.OS)
	if degraded {
		c.Log.Warn("当前平台不支持 mode=ac，已降级为 always（拔电也会阻止睡眠）")
	}
	if !c.available() {
		if c.OS == platform.Unknown {
			return ErrUnsupported
		}
		return fmt.Errorf("%w: 需要 %s", ErrUnavailable, backendName(c.Env, eff, c.OS))
	}
	if c.DryRun {
		c.Log.Info("[DRY-RUN] 将开启防休眠 " + eff.String())
		return nil
	}
	if st, ok := c.loadState(); ok && c.alive(st) {
		// 参数变了（如 on --display）：不能当作幂等直接返回，必须按新 spec 重启后端，
		// 否则断言参数（是否含 -d / ES_DISPLAY_REQUIRED）与期望不一致。
		if st.Mode == string(eff.Mode) && st.Display == eff.Display {
			c.Log.Info("防休眠已在生效" + pidSuffix(st.PID))
			return nil
		}
		c.Log.Info("防休眠参数已变化，重启后端")
		c.stopRuntime(st)
	}
	c.clearState()
	if c.OS == platform.Windows {
		if err := c.writeWindowsScript(eff); err != nil {
			return err
		}
	}
	if eff.Persist {
		return c.onPersist(eff)
	}

	call := backendFor(c.Env, eff, c.OS)
	pid, err := c.Run.Start(call.Name, call.Args...)
	if err != nil {
		return fmt.Errorf("启动 %s 失败: %w", call.Kind, err)
	}
	st := State{PID: pid, Mode: string(eff.Mode), Display: eff.Display, Backend: call.Kind,
		ManagedBy: "process", StartedAt: nowStamp()}
	if err := c.saveState(st); err != nil {
		_ = c.Run.Kill(pid)
		return err
	}
	if !c.waitAssertion(st) {
		_ = c.Run.Kill(pid)
		c.clearState()
		return fmt.Errorf("断言未注册（%s 可能被系统拒绝）", call.Kind)
	}
	c.Log.Success("防休眠已开启" + pidSuffix(pid))
	return nil
}

func (c *Controller) waitAssertion(st State) bool {
	for i := 0; i < 5; i++ {
		if c.assertionHeld(st) {
			return true
		}
		time.Sleep(200 * time.Millisecond)
	}
	return false
}

// onPersist 写入自启单元并立即加载（登录后自动恢复）。
func (c *Controller) onPersist(spec Spec) error {
	if c.OS == platform.Windows {
		return c.onPersistWindows(spec)
	}
	uf := unitFileFor(c.Env, spec, c.OS)
	backup, err := c.writeAsset(uf.Path, uf.Content)
	if err != nil {
		return fmt.Errorf("写入自启单元失败: %w", err)
	}
	rollback := func() { _ = engine.RemoveOwnedFile(uf.Path, backup) }

	var pid int
	switch c.OS {
	case platform.MacOS:
		domain := launchctlDomain()
		_, _ = c.Run.Run("launchctl", "bootout", domain+"/"+Label) // 幂等：先拆旧
		if _, err := c.Run.Run("launchctl", "bootstrap", domain, uf.Path); err != nil {
			rollback()
			return fmt.Errorf("加载 LaunchAgent 失败: %w", err)
		}
		pid = c.launchAgentPID(domain + "/" + Label)
	case platform.Linux:
		_, _ = c.Run.Run("systemctl", "--user", "daemon-reload")
		if _, err := c.Run.Run("systemctl", "--user", "enable", "--now", SystemdUnit); err != nil {
			rollback()
			return fmt.Errorf("启用 systemd 单元失败: %w", err)
		}
		pid = c.systemdMainPID()
	}
	st := State{PID: pid, Mode: string(spec.Mode), Display: spec.Display, Backend: backendFor(c.Env, spec, c.OS).Kind,
		ManagedBy: "launchagent", StartedAt: nowStamp(), Backup: backup}
	if c.OS == platform.Linux {
		st.ManagedBy = "systemd"
	}
	if err := c.saveState(st); err != nil {
		return err
	}
	c.Log.Success("防休眠已开启并设置开机自启" + pidSuffix(pid))
	return nil
}

func (c *Controller) onPersistWindows(spec Spec) error {
	if err := c.writeWindowsScript(spec); err != nil {
		return err
	}
	uf := unitFileFor(c.Env, spec, c.OS)
	backup, err := c.writeAsset(uf.Path, uf.Content)
	if err != nil {
		return fmt.Errorf("写入启动器失败: %w", err)
	}
	if _, err := c.Run.Run("schtasks", "/Create", "/TN", WinTaskName, "/TR", uf.Path,
		"/SC", "ONLOGON", "/RL", "LIMITED", "/F"); err != nil {
		c.Log.Warn("创建计划任务失败（本次仍会生效，但重启后不会自动恢复）: " + err.Error())
	}
	call := backendFor(c.Env, spec, c.OS)
	pid, err := c.Run.Start(call.Name, call.Args...)
	if err != nil {
		_ = engine.RemoveOwnedFile(uf.Path, backup)
		return fmt.Errorf("启动 %s 失败: %w", call.Kind, err)
	}
	st := State{PID: pid, Mode: string(spec.Mode), Display: spec.Display, Backend: call.Kind,
		ManagedBy: "process", StartedAt: nowStamp(), Backup: backup}
	if err := c.saveState(st); err != nil {
		_ = c.Run.Kill(pid)
		return err
	}
	c.Log.Success("防休眠已开启并设置登录自启" + pidSuffix(pid))
	return nil
}

func (c *Controller) launchAgentPID(target string) int {
	for i := 0; i < 10; i++ {
		out, err := c.Run.Run("launchctl", "print", target)
		if err == nil {
			if pid := parseLaunchctlPID(out); pid > 0 {
				return pid
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	return 0
}

func parseLaunchctlPID(out string) int {
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "pid = ") {
			if n, err := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(line, "pid = "))); err == nil {
				return n
			}
		}
	}
	return 0
}

func (c *Controller) systemdMainPID() int {
	out, err := c.Run.Run("systemctl", "--user", "show", "-p", "MainPID", "--value", SystemdUnit)
	if err != nil {
		return 0
	}
	n, _ := strconv.Atoi(strings.TrimSpace(out))
	return n
}

// writeAsset 写入 EasyWork 专属资产文件。
// 已是 EasyWork 生成的内容直接覆盖（避免每次改参数都堆一个 .bak）；
// 仅当接管「别人的同名文件」时才备份并记录，供卸载还原。
func (c *Controller) writeAsset(path, content string) (string, error) {
	if data, err := os.ReadFile(path); err == nil && strings.Contains(string(data), "EasyWork") {
		return "", platform.AtomicWrite(path, []byte(content), 0o644)
	}
	return engine.ApplyOwnedFile(path, []byte(content), 0o644)
}

// writeWindowsScript 落盘 PowerShell 常驻脚本（整文件接管）。
func (c *Controller) writeWindowsScript(spec Spec) error {
	if c.DryRun {
		return nil
	}
	if _, err := c.writeAsset(windowsScriptPath(c.Env), windowsScript(spec.Display)); err != nil {
		return fmt.Errorf("写入 Windows 常驻脚本失败: %w", err)
	}
	return nil
}

// Off 停止防休眠并拆除自启（幂等，恒成功）。
func (c *Controller) Off() error {
	if c.DryRun {
		c.Log.Info("[DRY-RUN] 将关闭防休眠并拆除自启")
		return nil
	}
	st, hasState := c.loadState()
	c.removePersist(st)
	if hasState {
		c.stopRuntime(st)
	}
	c.clearState()
	c.removeWindowsScript()
	c.Log.Success("防休眠已关闭")
	return nil
}

// removeWindowsScript 清理 Windows 常驻脚本（只删含 EasyWork 标记的文件）。
func (c *Controller) removeWindowsScript() {
	if c.OS != platform.Windows || c.DryRun {
		return
	}
	path := windowsScriptPath(c.Env)
	if data, err := os.ReadFile(path); err == nil && strings.Contains(string(data), "EasyWork keepawake") {
		_ = os.Remove(path)
	}
	// 清理历史遗留的备份（早期版本每次改参数都会生成一个 .bak）
	if matches, err := filepath.Glob(filepath.Join(c.Env.EasyworkHome, "keepawake.*.bak.*")); err == nil {
		for _, m := range matches {
			_ = os.Remove(m)
		}
	}
}

// stopRuntime 停止当前运行态（自启单元由 removePersist 负责，此处只处理普通进程）。
func (c *Controller) stopRuntime(st State) {
	if st.ManagedBy == "launchagent" || st.ManagedBy == "systemd" || st.PID <= 0 {
		return
	}
	_ = c.Run.Kill(st.PID)
}

// removePersist 拆除自启单元（无论状态文件是否存在都尽力执行）。
func (c *Controller) removePersist(st State) {
	uf := unitFileFor(c.Env, c.effective(st), c.OS)
	if _, err := os.Stat(uf.Path); err != nil {
		return
	}
	if !ownsUnit(uf.Path, c.OS) {
		return
	}
	switch c.OS {
	case platform.MacOS:
		_, _ = c.Run.Run("launchctl", "bootout", launchctlDomain()+"/"+Label)
	case platform.Linux:
		_, _ = c.Run.Run("systemctl", "--user", "disable", "--now", SystemdUnit)
	case platform.Windows:
		_, _ = c.Run.Run("schtasks", "/Delete", "/TN", WinTaskName, "/F")
	}
	if err := engine.RemoveOwnedFile(uf.Path, st.Backup); err != nil {
		c.Log.Warn("移除自启单元失败: " + err.Error())
	} else {
		c.Log.Info("已移除开机自启")
	}
	if c.OS == platform.Linux {
		_, _ = c.Run.Run("systemctl", "--user", "daemon-reload")
	}
}

// ownsUnit 校验目标文件确实是 EasyWork 生成的（避免误删同名文件）。
func ownsUnit(path string, osName platform.OS) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	marker := Label
	if osName == platform.Linux {
		marker = "EasyWork keepawake"
	}
	if osName == platform.Windows {
		marker = "EasyWork keepawake launcher"
	}
	return strings.Contains(string(data), marker)
}

// Status 探测真实状态（只读，不写盘）。
func (c *Controller) Status(spec Spec) Status {
	spec = spec.Normalized()
	eff, degraded := spec.Effective(c.OS)
	out := Status{Desired: spec, ModeDegraded: degraded, Platform: string(c.OS)}
	if !c.available() {
		out.Actual.State = StateUnsupported
		return out
	}
	st, ok := c.loadState()
	if !ok {
		out.Actual.State = StateInactive
		return out
	}
	st = c.refreshPID(st)
	if !c.alive(st) {
		out.Actual.State = StateInactive
		return out
	}
	out.Actual.PID = st.PID
	out.Actual.Backend = st.Backend
	out.Actual.ManagedBy = st.ManagedBy
	out.Actual.Since = st.StartedAt
	if !c.assertionHeld(st) {
		out.Actual.State = StateStale
		return out
	}
	ac := c.powerAC()
	out.Actual.ACPower = &ac
	out.Actual.Assertion = assertionName(c.OS)
	if c.OS == platform.MacOS && eff.Mode == ModeAC && !ac {
		out.Actual.State = StatePendingAC
		return out
	}
	out.Actual.State = StateActive
	return out
}

// backendName 返回后端可执行名（错误提示用）。
func backendName(env platform.Env, spec Spec, osName platform.OS) string {
	call := backendFor(env, spec, osName)
	return call.Name
}

func pidSuffix(pid int) string {
	if pid <= 0 {
		return ""
	}
	return " (pid " + strconv.Itoa(pid) + ")"
}

func nowStamp() string { return time.Now().Format("2006-01-02T15:04:05-0700") }
