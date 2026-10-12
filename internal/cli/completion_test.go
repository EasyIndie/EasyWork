package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// EASYWORK_HOME 变更后，rc/profile 中过期的补全 source 行应被自动纠正。
func TestSetupCompletionsUpdatesStalePath(t *testing.T) {
	home := t.TempDir()
	env := platform.Env{Home: home, EasyworkHome: filepath.Join(home, ".easywork"), TempDir: t.TempDir()}
	app := &App{Env: env, Log: logx.New(), Version: "0.1.0"}

	rcs := app.completionRCFiles()
	if len(rcs) == 0 {
		t.Fatal("no completion rc files for current platform")
	}
	rc := rcs[0]
	stale := "source /old/tmp/.easywork/completions/easywork.bash  # EasyWork completion\n"
	if err := os.WriteFile(rc.path, []byte("export FOO=1\n"+stale), 0o644); err != nil {
		t.Fatal(err)
	}

	if code := app.setupCompletions(); code != 0 {
		t.Fatalf("setupCompletions rc=%d", code)
	}
	data, err := os.ReadFile(rc.path)
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	if strings.Contains(got, "/old/tmp") {
		t.Fatalf("stale line not removed:\n%s", got)
	}
	want := app.completionSourceLine(rc.shell, env.CompletionsDir())
	if !rcHasLine(rc.path, want) {
		t.Fatalf("expected updated line %q in:\n%s", want, got)
	}
	if !strings.Contains(got, "export FOO=1") {
		t.Fatalf("user content lost:\n%s", got)
	}

	before := got
	if code := app.setupCompletions(); code != 0 {
		t.Fatalf("second setup rc=%d", code)
	}
	after, _ := os.ReadFile(rc.path)
	if string(after) != before {
		t.Fatalf("not idempotent:\nbefore:\n%s\nafter:\n%s", before, string(after))
	}
}
