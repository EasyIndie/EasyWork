package engine

import (
	"bytes"
	"os"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// ─── Owned file 原语（契约六的补充，见 docs/spec/08-keepawake.md §11） ──
//
// Managed section 依赖注释标记，无法用于 plist / systemd unit 这类
// 「整体文件即内容」的目标。Owned file 语义：EasyWork 独占该文件，
// 首次接管前把用户原有内容备份为 <target>.bak.<stamp>，卸载时还原。

// ApplyOwnedFile 以整文件方式写入 target，返回接管前的备份路径（无备份时为空）。
// 内容完全一致时为 no-op（幂等）。
func ApplyOwnedFile(target string, content []byte, perm os.FileMode) (string, error) {
	existing, err := os.ReadFile(target)
	if err == nil && bytes.Equal(existing, content) {
		return "", nil
	}
	backup := ""
	if err == nil {
		b, berr := BackupFile(target)
		if berr != nil {
			return "", berr
		}
		backup = b
	}
	if werr := platform.AtomicWrite(target, content, perm); werr != nil {
		return "", werr
	}
	return backup, nil
}

// RemoveOwnedFile 删除 target；backup 非空且存在时优先还原备份（幂等）。
func RemoveOwnedFile(target, backup string) error {
	if backup != "" {
		if _, err := os.Stat(backup); err == nil {
			return RestoreBackup(backup, target)
		}
	}
	if err := os.Remove(target); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
