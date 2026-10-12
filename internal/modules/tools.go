package modules

import (
	"os"
	"os/exec"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// ─── 可选外部工具通用安装器 ──────────────────────────────────
//
// 策略：不安装 GUI 应用，**但终端模拟器除外**（终端模拟器允许安装）。
// 可选模块（OptionalModule）默认不在 `ew install`（无参数）中安装，
// 只有显式 `ew install <tool>` 才安装；且模块 Platforms() 未包含当前平台时
// 由编排层跳过（"仅平台有支持版本时安装"）。

// toolSpec 描述一个外部工具的安装方式。
type toolSpec struct {
	cmd        string // 用于幂等检测的命令（GUI 应用可配合 brewCask 检查 /Applications）
	brewCask   bool   // brew 用 --cask（GUI 应用，如终端模拟器）
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
	if toolPresent(spec) {
		ctx.Log.Info(spec.cmd + " 已安装")
		return ctx.Manifest.SetSection(name, "installed=true")
	}
	if ctx.Offline {
		ctx.Log.Warn("离线模式：跳过 " + name + " 安装")
		return nil
	}

	if installViaPackageManager(ctx, name, spec) || runOfficialScript(ctx, name, spec) {
		if !toolPresent(spec) {
			ctx.Log.Warn(name + " 安装后仍未检测到，请检查 PATH 或应用目录")
		}
		return ctx.Manifest.SetSection(name, "installed=true")
	}

	ctx.Log.Warn("未能自动安装 " + name + "，请手动安装: " + spec.url)
	return ctx.Manifest.SetSection(name, "installed=true")
}

// toolPresent 幂等检测：先在 PATH 找命令；GUI 应用（brewCask）再回退检查
// macOS 的 /Applications/<Name>.app（其 CLI 可能不在 PATH，如 Ghostty）。
func toolPresent(spec toolSpec) bool {
	if platform.HasCmd(spec.cmd) {
		return true
	}
	if spec.brewCask && platform.DetectOS() == platform.MacOS {
		if _, err := os.Stat("/Applications/" + spec.cmd + ".app"); err == nil {
			return true
		}
	}
	return false
}

func installViaPackageManager(ctx *Context, name string, spec toolSpec) bool {
	pm := platform.DetectPackageManager()
	if !pm.Known() {
		return false
	}
	ctx.Log.Info("使用 " + pm.Name() + " 安装 " + name + "...")
	if spec.brewCask {
		return pm.InstallCask(name) == nil
	}
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

// ─── ghostty：终端模拟器（GUI，属"终端模拟器除外"允许项）─────

type ghosttyModule struct{}

func (ghosttyModule) Name() string             { return "ghostty" }
func (ghosttyModule) Description() string      { return "Ghostty 终端（macOS / Linux）" }
func (ghosttyModule) Priority() int            { return 70 }
func (ghosttyModule) Platforms() []platform.OS { return []platform.OS{platform.MacOS, platform.Linux} }
func (ghosttyModule) Optional() bool           { return true }

func (ghosttyModule) Install(ctx *Context) error {
	return installOptionalTool(ctx, "ghostty", toolSpec{
		cmd:      "ghostty",
		brewCask: true,
		url:      "https://ghostty.org/download",
	})
}

func (m ghosttyModule) Uninstall(ctx *Context) error { return keepInstalledTool(ctx, m.Name()) }
