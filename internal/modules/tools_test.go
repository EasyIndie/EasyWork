package modules

import (
	"path/filepath"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

func extrasTestCtx(t *testing.T) *Context {
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

func platformSet(ps []platform.OS) map[platform.OS]bool {
	m := map[platform.OS]bool{}
	for _, p := range ps {
		m[p] = true
	}
	return m
}

func TestToolsPlatformSupport(t *testing.T) {
	cases := []struct {
		mod     Module
		macos   bool
		linux   bool
		windows bool
	}{
		{moleModule{}, true, false, true},    // Mole：macOS + 官方 Windows CLI
		{glowModule{}, true, true, true},     // glow：全平台
		{herdrModule{}, true, true, true},    // herdr：全平台
		{ghosttyModule{}, true, true, false}, // Ghostty：macOS / Linux（终端模拟器）
	}
	for _, c := range cases {
		got := platformSet(c.mod.Platforms())
		if got[platform.MacOS] != c.macos || got[platform.Linux] != c.linux || got[platform.Windows] != c.windows {
			t.Errorf("%s platforms = %v, want macos=%v linux=%v windows=%v",
				c.mod.Name(), c.mod.Platforms(), c.macos, c.linux, c.windows)
		}
	}
}

func TestToolsAreOptional(t *testing.T) {
	for _, name := range []string{"glow", "herdr", "mole", "ghostty"} {
		m, ok := ByName(name)
		if !ok {
			t.Fatalf("%s not registered", name)
		}
		if !IsOptional(m) {
			t.Errorf("%s should be optional", name)
		}
	}
	for _, name := range []string{"shell", "git", "gh", "vim", "ai"} {
		m, _ := ByName(name)
		if IsOptional(m) {
			t.Errorf("%s should NOT be optional", name)
		}
	}
}

func TestInstallOptionalToolDryRunDoesNotWriteManifest(t *testing.T) {
	for _, m := range []Module{glowModule{}, herdrModule{}, moleModule{}} {
		ctx := extrasTestCtx(t)
		ctx.DryRun = true
		if err := m.Install(ctx); err != nil {
			t.Fatalf("%s dry-run: %v", m.Name(), err)
		}
		if ctx.Manifest.Exists() {
			t.Errorf("%s dry-run should not write manifest", m.Name())
		}
	}
}

func TestInstallOptionalToolOfflineReturnsNil(t *testing.T) {
	for _, m := range []Module{glowModule{}, herdrModule{}, moleModule{}} {
		ctx := extrasTestCtx(t)
		ctx.Offline = true
		if err := m.Install(ctx); err != nil {
			t.Fatalf("%s offline: %v", m.Name(), err)
		}
	}
}
