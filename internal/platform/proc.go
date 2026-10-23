package platform

import (
	"errors"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// ProcessCmdline 返回进程的完整命令行；进程不存在或不可读时 ok=false。
// 用途：防休眠状态探测时校验 pid 身份，避免 pid 复用导致的误判。
func ProcessCmdline(pid int) (string, bool) {
	if pid <= 0 {
		return "", false
	}
	switch DetectOS() {
	case Linux:
		data, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/cmdline")
		if err != nil {
			return "", false
		}
		out := strings.ReplaceAll(strings.TrimRight(string(data), "\x00"), "\x00", " ")
		if strings.TrimSpace(out) == "" {
			return "", false
		}
		return out, true
	case MacOS:
		out, err := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "command=").Output()
		if err != nil {
			return "", false
		}
		s := strings.TrimSpace(string(out))
		return s, s != ""
	case Windows:
		// 注意：-Filter 必须用**单引号**。Go 传给 powershell 的参数若含双引号，
		// 会被 Windows 命令行转义规则改写（\" 不再等价），导致查询恒失败。
		script := "(Get-CimInstance Win32_Process -Filter 'ProcessId=" + strconv.Itoa(pid) + "').CommandLine"
		out, err := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", script).Output()
		if err != nil {
			return "", false
		}
		s := strings.TrimSpace(string(out))
		return s, s != ""
	}
	return "", false
}

// ProcessMatches 判定 pid 仍是同名进程（仅校验可执行映像名，不解析命令行）。
//
// Windows 上必须用 tasklist：SSH 会话常落在 session 0，WMI 的
// Win32_Process.CommandLine 对这类进程可能为 null，用它做身份校验会恒失败。
func ProcessMatches(pid int, image string) bool {
	if pid <= 0 {
		return false
	}
	if DetectOS() != Windows {
		cmdline, ok := ProcessCmdline(pid)
		return ok && strings.Contains(strings.ToLower(cmdline), strings.ToLower(image))
	}
	out, err := exec.Command("tasklist", "/FI", "PID eq "+strconv.Itoa(pid), "/NH", "/FO", "CSV").Output()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(out)), strings.ToLower(image))
}

// StartDetached 以脱离当前会话的方式启动进程，返回其 pid。
func StartDetached(name string, args ...string) (int, error) {
	return startDetached(name, args)
}

// KillProcess 尽力终止进程（不存在时返回 nil）。
func KillProcess(pid int) error {
	if pid <= 0 {
		return nil
	}
	p, err := os.FindProcess(pid)
	if err != nil {
		return nil
	}
	if err := p.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
		return err
	}
	return nil
}
