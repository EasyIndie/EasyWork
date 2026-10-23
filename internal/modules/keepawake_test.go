package modules

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

func keepawakeContext(t *testing.T) (*Context, platform.Env) {
	t.Helper()
	dir := t.TempDir()
	env := platform.Env{Home: dir, EasyworkHome: filepath.Join(dir, ".easywork"), TempDir: dir}
	if err := env.EnsureHome(); err != nil {
		t.Fatal(err)
	}
	ctx := &Context{
		Env:      env,
		Config:   engine.NewConfig(env),
		Manifest: engine.NewManifest(env),
		Version:  "test",
		Log:      logx.New(),
		DryRun:   true,
	}
	return ctx, env
}

func TestKeepawakeModuleMetadata(t *testing.T) {
	m := keepawakeModule{}
	if m.Name() != "keepawake" {
		t.Fatalf("Name 应为 keepawake，得到 %s", m.Name())
	}
	if !IsOptional(m) {
		t.Fatal("keepawake 应为可选模块（默认不装）")
	}
	if !Supports(m, platform.Linux) || !Supports(m, platform.MacOS) || !Supports(m, platform.Windows) {
		t.Fatal("keepawake 应支持全平台")
	}
	if m.Priority() <= 70 {
		t.Fatalf("keepawake 应在可选工具之后执行，priority=%d", m.Priority())
	}
}

// 显式安装且 config 未写 enabled → 视为开启（dry-run 不落盘）。
func TestKeepawakeInstallDefaultsToEnabled(t *testing.T) {
	ctx, env := keepawakeContext(t)
	m := keepawakeModule{}
	if err := m.Install(ctx); err != nil {
		t.Fatalf("Install 失败: %v", err)
	}
	cfg := engine.NewConfig(env)
	if cfg.Has("keepawake.enabled") {
		t.Fatal("dry-run 不应写配置")
	}
}

// config 显式 enabled=false → apply 收敛为关闭（不启动）。
func TestKeepawakeInstallHonorsDisabled(t *testing.T) {
	ctx, env := keepawakeContext(t)
	cfg := engine.NewConfig(env)
	if err := cfg.Set("keepawake.enabled", "false"); err != nil {
		t.Fatal(err)
	}
	ctx.Config = cfg
	if err := (keepawakeModule{}).Install(ctx); err != nil {
		t.Fatalf("Install 失败: %v", err)
	}
	// 关闭路径不应留下状态文件
	statePath := filepath.Join(env.EasyworkHome, "run", "keepawake.json")
	if _, err := os.Stat(statePath); err == nil {
		t.Fatal("enabled=false 时不得写入运行态")
	}
}
