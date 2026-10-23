//go:build windows

package platform

import (
	"os/exec"
	"syscall"
)

// Windows 进程创建标志。
const (
	// createNoWindow 无控制台窗口（Console 子系统仍可用）。
	// 注意：不能用 DETACHED_PROCESS(0x8) —— PowerShell 需要控制台子系统，
	// 脱离后会在建进程的瞬间静默 exit 0（实测：连纯 sleep 循环都不执行）。
	createNoWindow = 0x08000000
	// createNewProcessGroup 独立进程组（Ctrl+C 不互相影响）。
	createNewProcessGroup = 0x00000200
	// createBreakawayFromJob 脱离父进程所在的 Job 对象（SSH 会话断开会带 Job 杀子进程）。
	createBreakawayFromJob = 0x01000000
)

// startDetached 启动无控制台窗口且独立于父进程的进程。
//
// 必须先尝试 CREATE_BREAKAWAY_FROM_JOB：Windows OpenSSH 把会话放在带
// KILL_ON_JOB_CLOSE 的 Job 里，不脱离 Job 的话进程会随 SSH 断开被一起杀掉
// （实测：断开后再连 status 变 inactive）。不在 Job 中时该标志是 no-op；
// 若环境不允许 breakaway（ERROR_ACCESS_DENIED）则退回不带该标志。
func startDetached(name string, args []string) (int, error) {
	pid, err := startWithFlags(name, args, createNoWindow|createNewProcessGroup|createBreakawayFromJob)
	if err == nil {
		return pid, nil
	}
	return startWithFlags(name, args, createNoWindow|createNewProcessGroup)
}

func startWithFlags(name string, args []string, flags uint32) (int, error) {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: flags}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	_ = cmd.Process.Release()
	return pid, nil
}
