package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestNewEnvEasyworkHomeOverride(t *testing.T) {
	t.Setenv("HOME", "/tmp/ew-test-home")
	t.Setenv("EASYWORK_HOME", "/tmp/ew-test-home/custom")
	env := NewEnv()
	if env.EasyworkHome != "/tmp/ew-test-home/custom" {
		t.Fatalf("override not honored: %s", env.EasyworkHome)
	}
	if env.ConfigPath() != filepath.Join("/tmp/ew-test-home/custom", "config.toml") {
		t.Fatalf("config path wrong: %s", env.ConfigPath())
	}
}

func TestNewEnvDefaultHome(t *testing.T) {
	t.Setenv("HOME", "/tmp/ew-home")
	t.Setenv("EASYWORK_HOME", "")
	env := NewEnv()
	want := filepath.Join("/tmp/ew-home", ".easywork")
	if env.EasyworkHome != want {
		t.Fatalf("default home wrong: got %s want %s", env.EasyworkHome, want)
	}
}

func TestDetectOS(t *testing.T) {
	os := DetectOS()
	switch runtime.GOOS {
	case "darwin":
		if os != MacOS {
			t.Fatalf("want macos got %s", os)
		}
	case "linux":
		if os != Linux {
			t.Fatalf("want linux got %s", os)
		}
	case "windows":
		if os != Windows {
			t.Fatalf("want windows got %s", os)
		}
	}
}

func TestAtomicWrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sub", "file.txt")
	if err := AtomicWrite(path, []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "hello" {
		t.Fatalf("read back failed: %q err=%v", data, err)
	}
	// 覆盖写
	if err := AtomicWrite(path, []byte("world"), 0o644); err != nil {
		t.Fatal(err)
	}
	data, _ = os.ReadFile(path)
	if string(data) != "world" {
		t.Fatalf("overwrite failed: %q", data)
	}
}
