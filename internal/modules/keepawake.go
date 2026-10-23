package modules

import (
	"github.com/EasyIndie/EasyWork/internal/keepawake"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// ─── keepawake：设备防休眠（可选模块） ──────────────────────
//
// 只注册电源断言（macOS caffeinate / Linux systemd-inhibit / Windows
// SetThreadExecutionState），不修改系统电源策略、不调用 sudo。
// 语义与验收见 docs/spec/08-keepawake.md。

type keepawakeModule struct{}

func (keepawakeModule) Name() string             { return "keepawake" }
func (keepawakeModule) Description() string      { return "设备防休眠（长跑任务不中断）" }
func (keepawakeModule) Priority() int            { return 75 }
func (keepawakeModule) Platforms() []platform.OS { return allPlatforms() }
func (keepawakeModule) Optional() bool           { return true }

// Install 收敛到 config 的期望状态：
//   - [keepawake] enabled 缺省 → 显式安装即视为开启（并写回 true）；
//   - enabled = false 显式写出 → 视为关闭，停止运行态（apply 幂等）。
func (keepawakeModule) Install(ctx *Context) error {
	spec := keepawake.SpecFromConfig(ctx.Config)
	ctl := keepawake.NewController(ctx.Env, ctx.Log, ctx.DryRun)
	if !spec.Enabled {
		if ctx.Config.Has("keepawake.enabled") {
			ctx.Log.Info("config 中 keepawake.enabled=false，保持关闭")
			return ctl.Off()
		}
		spec.Enabled = true
		if ctx.DryRun {
			ctx.Log.Info("[DRY-RUN] 将写入 keepawake.enabled=true")
			return ctl.On(spec)
		}
		if err := ctx.Config.Set("keepawake.enabled", "true"); err != nil {
			return err
		}
	}
	return ctl.On(spec)
}

// Uninstall 停止防休眠并拆除自启（保留 config，遵循 --keep-config 语义）。
func (keepawakeModule) Uninstall(ctx *Context) error {
	return keepawake.NewController(ctx.Env, ctx.Log, ctx.DryRun).Off()
}
