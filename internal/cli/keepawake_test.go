package cli

import (
	"path/filepath"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/keepawake"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

func testApp(t *testing.T) *App {
	t.Helper()
	dir := t.TempDir()
	env := platform.Env{Home: dir, EasyworkHome: filepath.Join(dir, ".easywork"), TempDir: dir}
	return &App{Env: env, Config: engine.NewConfig(env), Manifest: engine.NewManifest(env), Log: logx.New(), Version: "test"}
}

func TestWriteKeepawakeConfigRoundTrip(t *testing.T) {
	app := testApp(t)
	spec := keepawake.Spec{Enabled: true, Mode: keepawake.ModeAlways, Display: true, Persist: true}
	if err := app.writeKeepawakeConfig(spec); err != nil {
		t.Fatalf("写入失败: %v", err)
	}
	got := keepawake.SpecFromConfig(app.Config)
	if got != spec {
		t.Fatalf("回读不一致: got=%+v want=%+v", got, spec)
	}
	// 关闭后 enabled 必须落盘为 false（apply 才不会自己开回来）
	if err := app.writeKeepawakeConfig(keepawake.Spec{Enabled: false, Mode: keepawake.ModeAlways}); err != nil {
		t.Fatal(err)
	}
	if keepawake.SpecFromConfig(app.Config).Enabled {
		t.Fatal("enabled=false 未生效")
	}
	if !app.Config.Has("keepawake.enabled") {
		t.Fatal("应显式写出 keepawake.enabled")
	}
}

func TestWriteKeepawakeConfigDryRunWritesNothing(t *testing.T) {
	app := testApp(t)
	app.DryRun = true
	if err := app.writeKeepawakeConfig(keepawake.Spec{Enabled: true, Mode: keepawake.ModeAC}); err != nil {
		t.Fatal(err)
	}
	if app.Config.Has("keepawake.enabled") {
		t.Fatal("--dry-run 不得写配置")
	}
}

func TestKeepawakeHints(t *testing.T) {
	cases := []struct {
		st   keepawake.Status
		want string
	}{
		{keepawake.Status{Actual: keepawake.Actual{State: keepawake.StatePendingAC}}, "接通电源"},
		{keepawake.Status{Actual: keepawake.Actual{State: keepawake.StateStale}}, "ew keepawake on"},
		{keepawake.Status{Desired: keepawake.Spec{Enabled: true}, Actual: keepawake.Actual{State: keepawake.StateInactive}}, "ew keepawake on"},
		{keepawake.Status{Actual: keepawake.Actual{State: keepawake.StateActive}}, "合盖"},
	}
	for _, c := range cases {
		if got := keepawakeHint(c.st); got == "" {
			t.Fatalf("%s 应有提示", c.st.Actual.State)
		} else if c.want != "" && !contains(got, c.want) {
			t.Fatalf("%s 提示应含 %q，得到 %q", c.st.Actual.State, c.want, got)
		}
	}
}

// 合盖提示只在 macOS 有意义（Linux/Windows 后端语义不同）。
func TestKeepawakeHintActiveIsPlatformSpecific(t *testing.T) {
	hint := keepawakeHint(keepawake.Status{Actual: keepawake.Actual{State: keepawake.StateActive}})
	if platform.DetectOS() == platform.MacOS {
		if !contains(hint, "合盖") {
			t.Fatalf("macOS 的 active 提示应包含合盖警告，得到 %q", hint)
		}
		return
	}
	if hint != "" {
		t.Fatalf("非 macOS 不应给出合盖提示，得到 %q", hint)
	}
}

func TestDescribeSpec(t *testing.T) {
	if got := describeSpec(keepawake.Spec{}); got != "关闭" {
		t.Fatalf("关闭描述错误: %q", got)
	}
	got := describeSpec(keepawake.Spec{Enabled: true, Mode: keepawake.ModeAC, Persist: true})
	if !contains(got, "mode=ac") || !contains(got, "persist=on") {
		t.Fatalf("开启描述错误: %q", got)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
