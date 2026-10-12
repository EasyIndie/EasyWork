package modules

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

func testGitCtx(t *testing.T) *Context {
	t.Helper()
	home := t.TempDir()
	env := platform.Env{Home: home, EasyworkHome: filepath.Join(home, ".easywork"), TempDir: t.TempDir()}
	return &Context{
		Env:      env,
		Config:   engine.NewConfig(env),
		Manifest: engine.NewManifest(env),
		Log:      logx.New(),
		Version:  "0.1.0",
	}
}

func TestGitConfigContentFullAliases(t *testing.T) {
	ctx := testGitCtx(t)
	got := gitConfigContent(ctx)
	for _, want := range []string{
		"[alias]",
		"cfg = config --global --list",
		"lgtg = log --oneline --tags",
		"smuir = submodule update --init --recursive",
		"sh = !git --no-pager show HEAD",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("git config missing %q", want)
		}
	}
}

func TestGitConfigContentUsesConfigIdentity(t *testing.T) {
	ctx := testGitCtx(t)
	_ = ctx.Config.Set("git.identities.personal.name", "张三")
	_ = ctx.Config.Set("git.identities.personal.email", "zhangsan@example.com")
	got := gitConfigContent(ctx)
	if !strings.Contains(got, "name = 张三") || !strings.Contains(got, "email = zhangsan@example.com") {
		t.Fatalf("identity not included:\n%s", got)
	}
}

func TestResolveGitIdentityFallsBackToGitGlobal(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows: 无法用无扩展名脚本 mock git（LookPath/PATHEXT）")
	}
	bin := t.TempDir()
	script := "#!/usr/bin/env bash\ncase \"$3\" in\n  user.name) echo FallbackUser ;;\n  user.email) echo fallback@example.com ;;\nesac\n"
	if err := os.WriteFile(filepath.Join(bin, "git"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	ctx := testGitCtx(t)
	name, email := resolveGitIdentity(ctx)
	if name != "FallbackUser" || email != "fallback@example.com" {
		t.Fatalf("got %q <%q>", name, email)
	}
}
