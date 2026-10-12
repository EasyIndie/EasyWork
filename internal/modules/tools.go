package modules

import (
	"os/exec"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// ─── 可选外部工具通用安装器 ──────────────────────────────────
//
// 仅安装 **CLI** 工具：不安装 GUI 应用，**终端模拟器除外**（终端模拟器一律不安装）。
// 可选模块（OptionalModule）默认不在 `ew install`（无参数）中安装，
// 只有显式 `ew install <tool>` 才安装；且模块 Platforms() 未包含当前平台时
// 由编排层跳过（"仅平台有支持版本时安装"）。

// toolSpec 描述一个外部 CLI 工具的安装方式。
type toolSpec struct {
	cmd        string // 用于幂等检测的命令
	unixScript string // 包管理器不可用时执行的官方安装脚本（sh -c）
	winScript  string // Windows 官方安装脚本（PowerShell -Command）
	url        string // 手动安装指引
}

// installOptionalTool 按「已安装 → 包管理器 → 官方脚本 → 指引」顺序安装。
func installOptionalTool(ctx *Context, name string, spec toolSpec) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将安装 " + name)
		return nil
	}
	if platform.HasCmd(spec.cmd) {
		ctx.Log.Info(spec.cmd + " 已安装")
		return ctx.Manifest.SetSection(name, "installed=true")
	}
	if ctx.Offline {
		ctx.Log.Warn("离线模式：跳过 " + name + " 安装")
		return nil
	}

	if installViaPackageManager(ctx, name, spec) || runOfficialScript(ctx, name, spec) {
		if !platform.HasCmd(spec.cmd) {
			ctx.Log.Warn(name + " 安装后仍未在 PATH 中找到，请检查 PATH")
		}
		return ctx.Manifest.SetSection(name, "installed=true")
	}

	ctx.Log.Warn("未能自动安装 " + name + "，请手动安装: " + spec.url)
	return ctx.Manifest.SetSection(name, "installed=true")
}

func installViaPackageManager(ctx *Context, name string, _ toolSpec) bool {
	pm := platform.DetectPackageManager()
	if !pm.Known() {
		return false
	}
	ctx.Log.Info("使用 " + pm.Name() + " 安装 " + name + "...")
	return pm.Install(name) == nil
}

func runOfficialScript(ctx *Context, name string, spec toolSpec) bool {
	if platform.DetectOS() == platform.Windows {
		if spec.winScript == "" {
			return false
		}
		ctx.Log.Info("运行 " + name + " 官方安装脚本（PowerShell）...")
		return exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", spec.winScript).Run() == nil
	}
	if spec.unixScript == "" {
		return false
	}
	ctx.Log.Info("运行 " + name + " 官方安装脚本...")
	return exec.Command("sh", "-c", spec.unixScript).Run() == nil
}

func keepInstalledTool(ctx *Context, name string) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将保留 " + name + "（不自动卸载）")
		return nil
	}
	ctx.Log.Info("保留已安装的 " + name + "（不自动卸载）")
	return nil
}

// ─── glow：终端 Markdown 渲染（CLI） ─────────────────────────

type glowModule struct{}

func (glowModule) Name() string             { return "glow" }
func (glowModule) Description() string      { return "终端 Markdown 渲染 (glow)" }
func (glowModule) Priority() int            { return 55 }
func (glowModule) Platforms() []platform.OS { return allPlatforms() }
func (glowModule) Optional() bool           { return true }

func (glowModule) Install(ctx *Context) error {
	return installOptionalTool(ctx, "glow", toolSpec{
		cmd: "glow",
		url: "https://github.com/charmbracelet/glow",
	})
}

func (m glowModule) Uninstall(ctx *Context) error { return keepInstalledTool(ctx, m.Name()) }

// ─── herdr：Agent 运行时（CLI） ──────────────────────────────

type herdrModule struct{}

func (herdrModule) Name() string             { return "herdr" }
func (herdrModule) Description() string      { return "Agent 运行时 (herdr)" }
func (herdrModule) Priority() int            { return 60 }
func (herdrModule) Platforms() []platform.OS { return allPlatforms() }
func (herdrModule) Optional() bool           { return true }

func (herdrModule) Install(ctx *Context) error {
	return installOptionalTool(ctx, "herdr", toolSpec{
		cmd:        "herdr",
		unixScript: "curl -fsSL https://herdr.dev/install.sh | sh",
		winScript:  "irm https://herdr.dev/install.ps1 | iex",
		url:        "https://herdr.dev",
	})
}

func (m herdrModule) Uninstall(ctx *Context) error { return keepInstalledTool(ctx, m.Name()) }

// ─── mole：macOS 清理与优化（CLI，命令 mo） ──────────────────

type moleModule struct{}

func (moleModule) Name() string             { return "mole" }
func (moleModule) Description() string      { return "macOS 清理与优化 (mole/mo)" }
func (moleModule) Priority() int            { return 65 }
func (moleModule) Platforms() []platform.OS { return []platform.OS{platform.MacOS, platform.Windows} }
func (moleModule) Optional() bool           { return true }

func (moleModule) Install(ctx *Context) error {
	return installOptionalTool(ctx, "mole", toolSpec{
		cmd:        "mo",
		unixScript: "curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash",
		winScript:  "iwr -useb https://raw.githubusercontent.com/tw93/Mole/windows/quick-install.ps1 | iex",
		url:        "https://github.com/tw93/Mole",
	})
}

func (m moleModule) Uninstall(ctx *Context) error { return keepInstalledTool(ctx, m.Name()) }
