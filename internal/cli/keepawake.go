package cli

import (
	"errors"
	"fmt"

	"github.com/EasyIndie/EasyWork/internal/keepawake"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// ─── keepawake：设备防休眠（契约八草案） ─────────────────────
//
// 命令语义：
//
//	ew keepawake on [--always] [--ac] [--display] [--persist]
//	ew keepawake off            写 enabled=false + 停断言 + 拆自启
//	ew keepawake status         只读探测（desired + actual）

func (a *App) cmdKeepawake(args []string) int {
	spec := keepawake.SpecFromConfig(a.Config)
	if len(args) == 0 {
		return a.keepawakeStatus(spec)
	}
	switch args[0] {
	case "status":
		return a.keepawakeStatus(spec)
	case "on":
		return a.keepawakeOn(args[1:], spec)
	case "off":
		return a.keepawakeOff(spec)
	default:
		return a.fail(1, "用法: ew keepawake <on|off|status> [--always|--ac] [--display] [--persist]")
	}
}

func (a *App) keepawakeOn(opts []string, spec keepawake.Spec) int {
	spec.Enabled = true
	for _, o := range opts {
		switch o {
		case "--always":
			spec.Mode = keepawake.ModeAlways
		case "--ac":
			spec.Mode = keepawake.ModeAC
		case "--display", "-d":
			spec.Display = true
		case "--persist", "-p":
			spec.Persist = true
		case "--no-persist":
			spec.Persist = false
		default:
			return a.fail(1, "未知选项: "+o+"（可用: --always --ac --display --persist）")
		}
	}
	spec = spec.Normalized()
	if err := a.writeKeepawakeConfig(spec); err != nil {
		return a.fail(1, "写入配置失败: "+err.Error())
	}
	ctl := keepawake.NewController(a.Env, a.Log, a.DryRun)
	if err := ctl.On(spec); err != nil {
		return a.keepawakeError(err)
	}
	a.markKeepawakeInstalled()
	return a.emitKeepawake(ctl.Status(spec))
}

// markKeepawakeInstalled 让 manifest 与运行态一致：否则 `ew keepawake on` 之后
// `ew status` 仍会显示 keepawake「未安装」。
func (a *App) markKeepawakeInstalled() {
	if a.DryRun {
		return
	}
	if !a.Manifest.Exists() {
		if err := a.Manifest.Init(a.Env, a.Version); err != nil {
			return
		}
	}
	_ = a.Manifest.SetSection("keepawake", "installed=true")
}

func (a *App) keepawakeOff(spec keepawake.Spec) int {
	spec.Enabled = false
	if err := a.writeKeepawakeConfig(spec); err != nil {
		return a.fail(1, "写入配置失败: "+err.Error())
	}
	ctl := keepawake.NewController(a.Env, a.Log, a.DryRun)
	if err := ctl.Off(); err != nil {
		return a.keepawakeError(err)
	}
	return a.emitKeepawake(ctl.Status(spec))
}

func (a *App) keepawakeStatus(spec keepawake.Spec) int {
	return a.emitKeepawake(keepawake.NewController(a.Env, a.Log, false).Status(spec))
}

// writeKeepawakeConfig 把期望状态写回 config.toml（--dry-run 时跳过）。
func (a *App) writeKeepawakeConfig(spec keepawake.Spec) error {
	if a.DryRun {
		return nil
	}
	if _, err := a.Config.Ensure(a.Env); err != nil {
		return err
	}
	if err := a.Config.Set("keepawake.enabled", boolText(spec.Enabled)); err != nil {
		return err
	}
	if err := a.Config.Set("keepawake.mode", string(spec.Mode)); err != nil {
		return err
	}
	if err := a.Config.Set("keepawake.display", boolText(spec.Display)); err != nil {
		return err
	}
	return a.Config.Set("keepawake.persist", boolText(spec.Persist))
}

func boolText(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// keepawakeError 把控制器错误映射为退出码（缺依赖/不支持 → 2）。
func (a *App) keepawakeError(err error) int {
	if errors.Is(err, keepawake.ErrUnavailable) || errors.Is(err, keepawake.ErrUnsupported) {
		return a.fail(2, err.Error())
	}
	return a.fail(1, err.Error())
}

// emitKeepawake 输出结果（--json 走信封，否则人类可读 + 下一步提示）。
func (a *App) emitKeepawake(st keepawake.Status) int {
	if a.JSON {
		a.emit("keepawake", st)
		return 0
	}
	fmt.Fprintf(a.Log.Out, "  期望  %s\n", describeSpec(st.Desired))
	fmt.Fprintf(a.Log.Out, "  实际  %s\n", describeActual(st))
	if hint := keepawakeHint(st); hint != "" {
		fmt.Fprintf(a.Log.Out, "  提示  %s\n", hint)
	}
	return 0
}

func describeSpec(spec keepawake.Spec) string {
	if !spec.Enabled {
		return "关闭"
	}
	out := "开启 mode=" + string(spec.Mode)
	if spec.Display {
		out += " display=on"
	}
	if spec.Persist {
		out += " persist=on"
	}
	return out
}

func describeActual(st keepawake.Status) string {
	actual := st.Actual
	switch actual.State {
	case keepawake.StateActive:
		return fmt.Sprintf("%s (pid %d, backend=%s)", actual.State, actual.PID, actual.Backend)
	case keepawake.StatePendingAC:
		return fmt.Sprintf("%s (pid %d, 当前电池供电)", actual.State, actual.PID)
	case keepawake.StateStale:
		return fmt.Sprintf("%s (pid %d 仍在，但断言已丢失)", actual.State, actual.PID)
	case keepawake.StateUnsupported:
		return actual.State + "（macOS 用 caffeinate；Linux 需 systemd-inhibit）"
	default:
		return actual.State
	}
}

func keepawakeHint(st keepawake.Status) string {
	switch st.Actual.State {
	case keepawake.StatePendingAC:
		return "接通电源后自动生效（拔电则恢复默认睡眠）"
	case keepawake.StateStale:
		return "断言已丢失，执行: ew keepawake on"
	case keepawake.StateInactive:
		if st.Desired.Enabled {
			return "配置为开启但未生效，执行: ew keepawake on"
		}
		return "执行: ew keepawake on 开启（先看 docs/spec/08-keepawake.md）"
	case keepawake.StateActive:
		if platform.DetectOS() == platform.MacOS {
			return "合盖仍会睡眠（笔记本均如此），长时间任务请保持开盖"
		}
	}
	return ""
}
