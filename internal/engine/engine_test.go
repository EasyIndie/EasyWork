package engine

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

func testEnv(t *testing.T) platform.Env {
	t.Helper()
	home := t.TempDir()
	return platform.Env{Home: home, EasyworkHome: filepath.Join(home, ".easywork"), TempDir: t.TempDir()}
}

func TestConfigSetGetRoundtrip(t *testing.T) {
	env := testEnv(t)
	c := NewConfig(env)
	if err := c.Set("git.identities.personal.name", `He said "hi" \ bye`); err != nil {
		t.Fatal(err)
	}
	got := c.Get("git.identities.personal.name", "")
	want := `He said "hi" \ bye`
	if got != want {
		t.Fatalf("roundtrip: got %q want %q", got, want)
	}
}

func TestConfigSetPreservesOtherKeys(t *testing.T) {
	env := testEnv(t)
	c := NewConfig(env)
	if err := os.MkdirAll(env.EasyworkHome, 0o755); err != nil {
		t.Fatal(err)
	}
	initial := "schema_version = 1\n# keep me\n[git]\nscope = \"global\"\n"
	if err := os.WriteFile(c.Path(), []byte(initial), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := c.Set("git.identity", "personal"); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(c.Path())
	if !contains(string(data), "# keep me") || !contains(string(data), `scope = "global"`) {
		t.Fatalf("unrelated keys not preserved:\n%s", data)
	}
	if c.Get("git.identity", "") != "personal" {
		t.Fatal("new key not readable")
	}
}

func TestConfigValid(t *testing.T) {
	env := testEnv(t)
	c := NewConfig(env)
	if !c.Valid() {
		t.Fatal("absent config should be valid")
	}
	if err := c.Set("schema_version", "2"); err != nil {
		t.Fatal(err)
	}
	// schema_version set via Set writes a quoted string "2"; still != "1"
	if c.Valid() {
		t.Fatal("schema_version=2 should be invalid")
	}
}

func TestManagedSectionIdempotent(t *testing.T) {
	env := testEnv(t)
	target := filepath.Join(env.Home, ".gitconfig")
	if _, err := ApplyManagedSection(target, "0.1.0", "alias.co=checkout", "#"); err != nil {
		t.Fatal(err)
	}
	first, _ := os.ReadFile(target)
	if _, err := ApplyManagedSection(target, "0.1.0", "alias.co=checkout", "#"); err != nil {
		t.Fatal(err)
	}
	second, _ := os.ReadFile(target)
	if string(first) != string(second) {
		t.Fatalf("not idempotent:\n%q\n%q", first, second)
	}
	if err := RemoveManagedSection(target); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(target)
	if contains(string(after), "managed section begin") {
		t.Fatal("section not removed")
	}
}

func TestManagedSectionBackupRestore(t *testing.T) {
	env := testEnv(t)
	target := filepath.Join(env.Home, ".gitconfig")
	original := "# user content\n[user]\n    name = bob\n"
	if err := os.WriteFile(target, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	backup, err := ApplyManagedSection(target, "0.1.0", "alias.co=checkout", "#")
	if err != nil || backup == "" {
		t.Fatalf("expected backup, got %q err=%v", backup, err)
	}
	if !contains(readFile(t, target), "# user content") {
		t.Fatal("user content lost")
	}
	if err := RemoveFile(target, backup); err != nil {
		t.Fatal(err)
	}
	if readFile(t, target) != original {
		t.Fatalf("restore mismatch: %q", readFile(t, target))
	}
}

func TestManifestStates(t *testing.T) {
	env := testEnv(t)
	m := NewManifest(env)
	if m.ModuleState("git") != "absent" {
		t.Fatal("expected absent")
	}
	if err := m.SetSection("git", "installed=true", "scope=global"); err != nil {
		t.Fatal(err)
	}
	if err := m.SetSection("vim", "installed=failed", "failed_at=T"); err != nil {
		t.Fatal(err)
	}
	if m.ModuleState("git") != "true" || m.ModuleState("vim") != "failed" {
		t.Fatalf("states wrong: %s %s", m.ModuleState("git"), m.ModuleState("vim"))
	}
	installed := m.ListInstalled()
	if len(installed) != 1 || installed[0] != "git" {
		t.Fatalf("list installed wrong: %v", installed)
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

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
