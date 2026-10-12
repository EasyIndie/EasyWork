package engine

import (
	"errors"
	"os"
	"strings"
	"time"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// errMalformedSection 表示缺少结束标记。
var errMalformedSection = errors.New("easywork: 检测到不完整的 managed section，已跳过修改")

// BeginMarker 生成 managed section 起始标记（契约六，逐字节固定）。
func BeginMarker(version, comment string) string {
	return comment + " >>> EasyWork managed section begin (v" + version + ") >>>"
}

// EndMarker 生成 managed section 结束标记。
func EndMarker(comment string) string {
	return comment + " <<< EasyWork managed section end <<<"
}

// BackupFile 复制 target 为 target.bak.<stamp>，返回备份路径。
func BackupFile(target string) (string, error) {
	if _, err := os.Stat(target); err != nil {
		return "", nil
	}
	data, err := os.ReadFile(target)
	if err != nil {
		return "", err
	}
	bak := target + ".bak." + time.Now().Format("20060102T150405")
	perm := os.FileMode(0o644)
	if fi, statErr := os.Stat(target); statErr == nil {
		perm = fi.Mode().Perm()
	}
	if err := platform.AtomicWrite(bak, data, perm); err != nil {
		return "", err
	}
	return bak, nil
}

// RestoreBackup 用备份覆盖 target，并删除备份（等价 Bash 的 mv）。
func RestoreBackup(bak, target string) error {
	data, err := os.ReadFile(bak)
	if err != nil {
		return err
	}
	if err := platform.AtomicWrite(target, data, 0o644); err != nil {
		return err
	}
	return os.Remove(bak)
}

// ApplyManagedSection 幂等写入 managed section；返回是否需要时创建的备份路径。
func ApplyManagedSection(target, version, content, comment string) (string, error) {
	data, err := os.ReadFile(target)
	if err != nil {
		body := strings.Join([]string{
			BeginMarker(version, comment),
			content,
			EndMarker(comment),
		}, "\n") + "\n"
		return "", platform.AtomicWrite(target, []byte(body), 0o644)
	}

	backup := ""
	if !strings.Contains(string(data), "EasyWork managed section") {
		b, berr := BackupFile(target)
		if berr != nil {
			return "", berr
		}
		backup = b
	}

	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	var out []string
	inSection := false
	hasSection := false
	for _, line := range lines {
		if strings.Contains(line, "managed section begin") {
			hasSection = true
			inSection = true
			out = append(out, BeginMarker(version, comment))
			out = append(out, strings.Split(content, "\n")...)
			continue
		}
		if strings.Contains(line, "managed section end") {
			inSection = false
			out = append(out, EndMarker(comment))
			continue
		}
		if !inSection {
			out = append(out, line)
		}
	}
	if !hasSection {
		// 前置注入：section + 空行 + 原内容
		var pre []string
		pre = append(pre, BeginMarker(version, comment))
		pre = append(pre, strings.Split(content, "\n")...)
		pre = append(pre, EndMarker(comment), "")
		pre = append(pre, lines...)
		out = pre
	}
	return backup, platform.AtomicWrite(target, []byte(strings.Join(out, "\n")+"\n"), 0o644)
}

// RemoveManagedSection 移除 managed section，保留其他内容。
func RemoveManagedSection(target string) error {
	data, err := os.ReadFile(target)
	if err != nil {
		return nil
	}
	if !strings.Contains(string(data), "managed section begin") {
		return nil
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	var out []string
	inSection := false
	for _, line := range lines {
		if strings.Contains(line, "managed section begin") {
			inSection = true
			continue
		}
		if inSection && strings.Contains(line, "managed section end") {
			inSection = false
			continue
		}
		if !inSection {
			out = append(out, line)
		}
	}
	if inSection {
		return errMalformedSection
	}
	content := ""
	if len(out) > 0 {
		content = strings.Join(out, "\n") + "\n"
	}
	return platform.AtomicWrite(target, []byte(content), 0o644)
}

// RemoveFile 移除 managed section 并按需还原备份（供模块卸载使用）。
func RemoveFile(target, backupPath string) error {
	_ = RemoveManagedSection(target)
	if backupPath != "" {
		if _, err := os.Stat(backupPath); err == nil {
			return RestoreBackup(backupPath, target)
		}
	}
	return nil
}
