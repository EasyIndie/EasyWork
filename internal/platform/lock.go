package platform

import (
	"errors"
	"os"
	"path/filepath"
	"time"
)

// ErrLockTimeout 表示在超时时间内未能获得锁（退出码 5）。
var ErrLockTimeout = errors.New("easywork: 获取锁超时")

// staleAfter 之后认为锁文件为陈旧锁，可回收。
const staleAfter = 60 * time.Second

// Lock 是基于 O_CREATE|O_EXCL 的跨平台文件锁。
type Lock struct {
	path string
}

// LockPath 返回状态根下的锁文件路径。
func LockPath(tempDir string) string { return filepath.Join(tempDir, "easywork.lock") }

// AcquireLock 在 timeout 内尝试获取锁，失败返回 ErrLockTimeout。
func AcquireLock(tempDir string, timeout time.Duration) (*Lock, error) {
	path := LockPath(tempDir)
	deadline := time.Now().Add(timeout)
	for {
		f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
		if err == nil {
			_ = f.Close()
			return &Lock{path: path}, nil
		}
		if !os.IsExist(err) {
			return nil, err
		}
		// 陈旧锁回收
		if fi, statErr := os.Stat(path); statErr == nil && time.Since(fi.ModTime()) > staleAfter {
			_ = os.Remove(path)
			continue
		}
		if time.Now().After(deadline) {
			return nil, ErrLockTimeout
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// Release 释放锁（幂等）。
func (l *Lock) Release() {
	if l == nil {
		return
	}
	_ = os.Remove(l.path)
}
