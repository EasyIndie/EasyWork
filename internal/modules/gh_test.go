package modules

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

func TestGHAptRepoLine(t *testing.T) {
	got := ghAptRepoLine("amd64", "/etc/apt/keyrings/githubcli-archive-keyring.gpg")
	want := "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] " +
		"https://cli.github.com/packages stable main"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestGHInstallStrategy(t *testing.T) {
	cases := map[string]string{
		"apt-get": "apt",
		"dnf":     "dnf",
		"yum":     "dnf",
		"brew":    "default",
		"winget":  "default",
		"scoop":   "default",
		"pacman":  "default",
		"unknown": "default",
	}
	for pm, want := range cases {
		if got := ghInstallStrategy(pm); got != want {
			t.Errorf("strategy(%s)=%s want %s", pm, got, want)
		}
	}
}

// TestSetupGHAptRepo 用 fake sudo/dpkg 验证官方 apt 源写入逻辑（无需 root）。
func TestSetupGHAptRepo(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("apt 源逻辑仅 Linux；Windows 用 winget/scoop/choco")
	}
	dir := t.TempDir()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("FAKE-KEYRING"))
	}))
	defer srv.Close()
	origURL := ghKeyringURL
	ghKeyringURL = srv.URL
	defer func() { ghKeyringURL = origURL }()

	binDir := filepath.Join(dir, "bin")
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		t.Fatal(err)
	}
	sudoLog := filepath.Join(dir, "sudo.log")
	writeScript(t, filepath.Join(binDir, "sudo"), "echo \"$@\" >> \""+sudoLog+"\"; exit 0\n")
	writeScript(t, filepath.Join(binDir, "dpkg"), "echo arm64\n")
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	ctx := &Context{Env: platform.Env{TempDir: dir, Home: dir}}
	if err := setupGHAptRepo(ctx); err != nil {
		t.Fatalf("setupGHAptRepo: %v", err)
	}

	keyring, err := os.ReadFile(filepath.Join(dir, "gh-keyring.gpg"))
	if err != nil || string(keyring) != "FAKE-KEYRING" {
		t.Fatalf("keyring download failed: %q err=%v", keyring, err)
	}

	list, err := os.ReadFile(filepath.Join(dir, "github-cli.list"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(list), "arch=arm64") || !strings.Contains(string(list), "stable main") {
		t.Fatalf("unexpected sources.list content: %q", list)
	}

	calls, _ := os.ReadFile(sudoLog)
	for _, want := range []string{
		"mkdir -p -m 755 /etc/apt/keyrings",
		"cp " + filepath.Join(dir, "gh-keyring.gpg") + " /etc/apt/keyrings/githubcli-archive-keyring.gpg",
		"cp " + filepath.Join(dir, "github-cli.list") + " /etc/apt/sources.list.d/github-cli.list",
		"apt-get update -y",
	} {
		if !strings.Contains(string(calls), want) {
			t.Errorf("sudo calls missing %q; got:\n%s", want, calls)
		}
	}
}

func writeScript(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte("#!/usr/bin/env bash\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
}
