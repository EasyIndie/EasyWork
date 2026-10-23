package engine

import (
	"os"
	"path/filepath"
	"testing"
)

func TestApplyOwnedFileCreates(t *testing.T) {
	target := filepath.Join(t.TempDir(), "sub", "unit.plist")
	backup, err := ApplyOwnedFile(target, []byte("content"), 0o644)
	if err != nil {
		t.Fatalf("写入失败: %v", err)
	}
	if backup != "" {
		t.Fatalf("新建文件不应产生备份，得到 %q", backup)
	}
	data, err := os.ReadFile(target)
	if err != nil || string(data) != "content" {
		t.Fatalf("内容不正确: %q err=%v", data, err)
	}
}

func TestApplyOwnedFileBacksUpForeignFile(t *testing.T) {
	target := filepath.Join(t.TempDir(), "unit.plist")
	if err := os.WriteFile(target, []byte("user-content"), 0o644); err != nil {
		t.Fatal(err)
	}
	backup, err := ApplyOwnedFile(target, []byte("easywork-content"), 0o644)
	if err != nil {
		t.Fatalf("写入失败: %v", err)
	}
	if backup == "" {
		t.Fatal("接管既有文件应产生备份")
	}
	if got, _ := os.ReadFile(backup); string(got) != "user-content" {
		t.Fatalf("备份内容不正确: %q", got)
	}
	if got, _ := os.ReadFile(target); string(got) != "easywork-content" {
		t.Fatalf("目标内容未替换: %q", got)
	}
}

func TestApplyOwnedFileIdempotent(t *testing.T) {
	target := filepath.Join(t.TempDir(), "unit.service")
	content := []byte("[Unit]\nDescription=x\n")
	if _, err := ApplyOwnedFile(target, content, 0o644); err != nil {
		t.Fatal(err)
	}
	backup, err := ApplyOwnedFile(target, content, 0o644)
	if err != nil {
		t.Fatalf("重复写入失败: %v", err)
	}
	if backup != "" {
		t.Fatalf("内容一致时不应产生备份，得到 %q", backup)
	}
}

func TestRemoveOwnedFileRestoresBackup(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "unit.plist")
	if err := os.WriteFile(target, []byte("user-content"), 0o644); err != nil {
		t.Fatal(err)
	}
	backup, err := ApplyOwnedFile(target, []byte("easywork"), 0o644)
	if err != nil {
		t.Fatal(err)
	}
	if err := RemoveOwnedFile(target, backup); err != nil {
		t.Fatalf("移除失败: %v", err)
	}
	if got, _ := os.ReadFile(target); string(got) != "user-content" {
		t.Fatalf("应还原用户原内容，得到 %q", got)
	}
	if _, err := os.Stat(backup); !os.IsNotExist(err) {
		t.Fatal("还原后应删除备份文件")
	}
}

func TestRemoveOwnedFileWithoutBackup(t *testing.T) {
	target := filepath.Join(t.TempDir(), "unit.service")
	if _, err := ApplyOwnedFile(target, []byte("easywork"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := RemoveOwnedFile(target, ""); err != nil {
		t.Fatalf("移除失败: %v", err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatal("无备份时应删除文件")
	}
	// 幂等：再删一次不报错
	if err := RemoveOwnedFile(target, ""); err != nil {
		t.Fatalf("重复移除应幂等: %v", err)
	}
}
