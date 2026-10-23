// Package keepawake 实现设备防休眠（契约八草案，见 docs/spec/08-keepawake.md）。
//
// 设计要点：
//   - 只用 caffeinate/systemd-inhibit 的**断言**，不修改系统电源策略（无 sudo）；
//   - macOS 默认 -s：接电生效、拔电由 powerd 自动忽略、重新接电自动恢复；
//   - 运行态 = 一个持断言的进程 + $EASYWORK_HOME/run/keepawake.json。
package keepawake

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// Mode 是防休眠模式。
type Mode string

const (
	// ModeAC 仅在接通电源时阻止系统睡眠（笔记本默认）。
	ModeAC Mode = "ac"
	// ModeAlways 任何供电都阻止系统睡眠（耗电，需显式选择）。
	ModeAlways Mode = "always"
)

// Spec 是一次防休眠的期望状态。
type Spec struct {
	Enabled bool `json:"enabled"`
	Mode    Mode `json:"mode"`
	Display bool `json:"display"`
	Persist bool `json:"persist"`
}

// Normalized 归一化非法 mode（未知值按 ac 处理）。
func (s Spec) Normalized() Spec {
	switch s.Mode {
	case ModeAC, ModeAlways:
	default:
		s.Mode = ModeAC
	}
	return s
}

// Effective 返回当前平台上实际生效的 spec，以及是否发生了降级。
// Linux/Windows 没有「仅接电时才生效」的等价断言，故降级为 always 并标记。
func (s Spec) Effective(os platform.OS) (Spec, bool) {
	s = s.Normalized()
	if os == platform.MacOS {
		return s, false
	}
	if s.Mode == ModeAC {
		s.Mode = ModeAlways
		return s, true
	}
	return s, false
}

// String 返回人类可读摘要（日志用）。
func (s Spec) String() string {
	state := "关闭"
	if s.Enabled {
		state = "开启"
	}
	return fmt.Sprintf("%s (mode=%s, display=%t, persist=%t)", state, s.Mode, s.Display, s.Persist)
}

// ─── 后端 ─────────────────────────────────────────────────────

// 自启单元标识（持久化用）。
const (
	// Label 是 macOS LaunchAgent 的 label。
	Label = "com.easyindie.easywork.keepawake"
	// SystemdUnit 是 Linux 的用户级 systemd 单元名。
	SystemdUnit = "easywork-keepawake.service"
	// WinTaskName 是 Windows 计划任务名。
	WinTaskName = "EasyWorkKeepawake"
)

// backendCall 描述如何启动一个持有断言的后端进程。
type backendCall struct {
	Kind   string   // caffeinate | systemd-inhibit | powershell
	Name   string   // 可执行文件
	Args   []string // 参数
	Marker string   // 用于校验 pid 身份的命令行片段
}

// windowsScriptPath 是 Windows 常驻脚本路径（以 -File 方式执行，避免命令行引号地狱）。
func windowsScriptPath(env platform.Env) string {
	return filepath.Join(env.EasyworkHome, "keepawake.ps1")
}

// windowsScript 返回 Windows 常驻脚本正文：每 30 秒续订一次执行状态断言。
// 0x80000001 = ES_CONTINUOUS | ES_SYSTEM_REQUIRED（含显示则为 0x80000003）。
//
// 说明：不能用 `powershell -Command "<内联代码>"` —— 代码里的双引号（DllImport）
// 会与 Windows 命令行转义规则冲突，实测进程秒退。写成 .ps1 再 -File 执行最稳。
func windowsScript(display bool) string {
	flags := "2147483649" // 0x80000001
	if display {
		flags = "2147483651" // 0x80000003
	}
	return "# EasyWork keepawake script (auto-generated) - do not edit\r\n" +
		`$s='[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'` +
		`;$t=Add-Type -MemberDefinition $s -Name KA -Namespace EW -PassThru` +
		`;while($true){[void]$t::SetThreadExecutionState([uint32]` + flags + `);Start-Sleep -Seconds 30}` + "\r\n"
}

// backendFor 按平台构造后端调用。
func backendFor(env platform.Env, spec Spec, osName platform.OS) backendCall {
	switch osName {
	case platform.MacOS:
		args := []string{}
		if spec.Display {
			args = append(args, "-d")
		}
		args = append(args, "-s") // 仅在接电时被 powerd 采纳
		if spec.Mode == ModeAlways {
			args = append(args, "-i")
		}
		return backendCall{Kind: "caffeinate", Name: "/usr/bin/caffeinate", Args: args, Marker: "caffeinate"}
	case platform.Linux:
		// --what=sleep:idle：阻止空闲/挂起；display 由桌面环境自行处理
		call := backendCall{
			Kind:   "systemd-inhibit",
			Name:   "systemd-inhibit",
			Args:   []string{"--what=sleep:idle", "--who=EasyWork", "--why=EasyWork-keepawake", "sleep", "infinity"},
			Marker: "systemd-inhibit",
		}
		if p, err := exec.LookPath("systemd-inhibit"); err == nil {
			call.Name = p
		}
		return call
	case platform.Windows:
		script := windowsScriptPath(env)
		call := backendCall{
			Kind:   "powershell",
			Name:   "powershell",
			Args:   []string{"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script},
			Marker: filepath.Base(script),
		}
		if p, err := exec.LookPath("powershell"); err == nil {
			call.Name = p
		}
		return call
	}
	return backendCall{Kind: "unsupported"}
}

// backendAvailable 报告当前平台是否具备可用的防休眠后端。
func backendAvailable(osName platform.OS) bool {
	switch osName {
	case platform.MacOS:
		_, err := os.Stat("/usr/bin/caffeinate")
		return err == nil
	case platform.Linux:
		_, err := exec.LookPath("systemd-inhibit")
		return err == nil
	case platform.Windows:
		_, err := exec.LookPath("powershell")
		return err == nil
	}
	return false
}

// ─── 自启单元（persist=true） ─────────────────────────────────

// unitFile 描述一个自启单元文件。
type unitFile struct {
	Path    string
	Content string
}

// unitPath 返回自启单元路径（Windows 为启动器脚本路径）。
func unitPath(env platform.Env, osName platform.OS) string {
	switch osName {
	case platform.MacOS:
		return filepath.Join(env.Home, "Library", "LaunchAgents", Label+".plist")
	case platform.Linux:
		return filepath.Join(env.Home, ".config", "systemd", "user", SystemdUnit)
	case platform.Windows:
		return filepath.Join(env.EasyworkHome, "keepawake.cmd")
	}
	return ""
}

// unitFileFor 生成自启单元内容。
func unitFileFor(env platform.Env, spec Spec, osName platform.OS) unitFile {
	call := backendFor(env, spec, osName)
	path := unitPath(env, osName)
	switch osName {
	case platform.MacOS:
		return unitFile{Path: path, Content: launchAgentPlist(env, call)}
	case platform.Linux:
		return unitFile{Path: path, Content: systemdUnitText(call)}
	case platform.Windows:
		return unitFile{Path: path, Content: windowsLauncher(call)}
	}
	return unitFile{Path: path}
}

// launchAgentPlist 生成 LaunchAgent（整文件接管，见 engine.ApplyOwnedFile）。
func launchAgentPlist(env platform.Env, call backendCall) string {
	args := make([]string, 0, len(call.Args)+1)
	args = append(args, xmlEscape(call.Name))
	for _, a := range call.Args {
		args = append(args, xmlEscape(a))
	}
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	b.WriteString(`<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">` + "\n")
	b.WriteString(`<plist version="1.0">` + "\n<dict>\n")
	b.WriteString("\t<key>Label</key><string>" + Label + "</string>\n")
	b.WriteString("\t<key>ProgramArguments</key>\n\t<array>\n")
	for _, a := range args {
		b.WriteString("\t\t<string>" + a + "</string>\n")
	}
	b.WriteString("\t</array>\n")
	b.WriteString("\t<key>RunAtLoad</key><true/>\n")
	b.WriteString("\t<key>KeepAlive</key><true/>\n")
	b.WriteString("\t<key>ProcessType</key><string>Background</string>\n")
	b.WriteString("\t<key>StandardErrorPath</key><string>" + xmlEscape(filepath.Join(env.EasyworkHome, "log", "keepawake.log")) + "</string>\n")
	b.WriteString("</dict>\n</plist>\n")
	return b.String()
}

// systemdUnitText 生成用户级 systemd 单元。
func systemdUnitText(call backendCall) string {
	exec := call.Name
	for _, a := range call.Args {
		if strings.ContainsAny(a, " \t\"") {
			exec += " \"" + strings.ReplaceAll(a, "\"", "\\\"") + "\""
		} else {
			exec += " " + a
		}
	}
	return "[Unit]\nDescription=EasyWork keepawake (prevent idle sleep)\n\n" +
		"[Service]\nType=simple\nExecStart=" + exec + "\nRestart=always\nRestartSec=5\n\n" +
		"[Install]\nWantedBy=default.target\n"
}

// windowsLauncher 生成计划任务调用的启动器脚本，避免 schtasks /TR 的嵌套引号问题。
func windowsLauncher(call backendCall) string {
	line := "powershell"
	for _, a := range call.Args {
		line += " " + winQuote(a)
	}
	return "@echo off\r\nrem EasyWork keepawake launcher (auto-generated)\r\n" + line + "\r\n"
}

func winQuote(s string) string {
	if !strings.ContainsAny(s, " \t\"") {
		return s
	}
	return `"` + strings.ReplaceAll(s, `"`, `\"`) + `"`
}

func xmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&apos;")
	return r.Replace(s)
}

// currentUID 返回当前用户 uid（Windows 为 -1）。
func currentUID() int { return os.Getuid() }

// execOutput 运行命令并返回 stdout（失败时返回已读到的输出）。
func execOutput(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	return string(out), err
}

// launchctlDomain 返回 gui/<uid> 域。
func launchctlDomain() string { return "gui/" + strconv.Itoa(currentUID()) }
