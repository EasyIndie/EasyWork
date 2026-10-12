package modules

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

func aiTestCtx(t *testing.T) *Context {
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

func toolCSV(tools []aiTool) string { return toolNames(tools) }

func TestAIModuleNameAndAliases(t *testing.T) {
	m := aiModule{}
	if m.Name() != "ai" {
		t.Fatalf("Name() = %q", m.Name())
	}
	if got := m.Aliases(); !reflect.DeepEqual(got, []string{"ai-tools"}) {
		t.Fatalf("Aliases() = %#v", got)
	}
	if got, ok := ByName("ai-tools"); !ok || got.Name() != "ai" {
		t.Fatalf("ByName(ai-tools) = %v, %v", got, ok)
	}
	if Canonical("ai-tools") != "ai" {
		t.Fatalf("Canonical(ai-tools) = %q", Canonical("ai-tools"))
	}
}

func TestAIToolsComponentsDeclared(t *testing.T) {
	got := aiModule{}.Components()
	want := []Component{
		{Name: "claude", Description: "Anthropic Claude Code（npm: @anthropic-ai/claude-code）"},
		{Name: "codex", Description: "OpenAI Codex CLI（npm: @openai/codex）"},
		{Name: "pi", Description: "Pi coding agent（npm: @earendil-works/pi-coding-agent）"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Components() = %#v", got)
	}
}

func TestSelectedToolsPrecedence(t *testing.T) {
	// 1. CLI selection wins.
	ctx := aiTestCtx(t)
	ctx.Selected = []string{"claude"}
	if got := toolCSV(selectedTools(ctx)); got != "claude" {
		t.Fatalf("CLI selection = %q", got)
	}

	// 2. config default subset（空格分隔）。
	ctx = aiTestCtx(t)
	_ = ctx.Config.Set("ai.tools", "codex pi")
	if got := toolCSV(selectedTools(ctx)); got != "codex,pi" {
		t.Fatalf("config subset = %q", got)
	}

	// 3. CLI overrides config.
	ctx.Selected = []string{"claude"}
	if got := toolCSV(selectedTools(ctx)); got != "claude" {
		t.Fatalf("CLI override = %q", got)
	}

	// 4. 旧配置键 ai_tools.tools 回退。
	ctx = aiTestCtx(t)
	_ = ctx.Config.Set("ai_tools.tools", "pi")
	if got := toolCSV(selectedTools(ctx)); got != "pi" {
		t.Fatalf("legacy config = %q", got)
	}

	// 5. nothing selected → all.
	ctx = aiTestCtx(t)
	if got := toolCSV(selectedTools(ctx)); got != "claude,codex,pi" {
		t.Fatalf("default = %q", got)
	}
}

func TestAIInstallEnabledLegacyFallback(t *testing.T) {
	ctx := aiTestCtx(t)
	if !aiInstallEnabled(ctx) {
		t.Fatal("default should be enabled")
	}
	_ = ctx.Config.Set("ai_tools.install", "false")
	if aiInstallEnabled(ctx) {
		t.Fatal("legacy ai_tools.install=false should disable")
	}
	_ = ctx.Config.Set("ai.install", "true")
	if !aiInstallEnabled(ctx) {
		t.Fatal("new ai.install=true should win over legacy")
	}
}
