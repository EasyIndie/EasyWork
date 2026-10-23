//go:build !windows

package platform

import (
	"os/exec"
	"syscall"
)

// startDetached 让子进程脱离父进程会话（终端关闭/父进程退出后仍存活）。
func startDetached(name string, args []string) (int, error) {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	_ = cmd.Process.Release()
	return pid, nil
}
