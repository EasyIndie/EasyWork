package modules

import (
	"os/exec"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

type aiModule struct{}

func (aiModule) Name() string             { return "ai" }
func (aiModule) Aliases() []string        { return []string{"ai-tools"} }
func (aiModule) Description() string      { return "安装 AI 编码 CLI（claude code / codex / pi）" }
func (aiModule) Priority() int            { return 50 }
func (aiModule) Platforms() []platform.OS { return allPlatforms() }

// aiTool 是 "<cli>:<npm package>" 的一项。
type aiTool struct{ cli, pkg string }

// aiTools 是模块的全部子组件（顺序即 `list` 展示顺序）。
var aiTools = []aiTool{
	{"claude", "@anthropic-ai/claude-code"},
	{"codex", "@openai/codex"},
	{"pi", "@earendil-works/pi-coding-agent"},
}

// Components 暴露子组件，使 ai 支持 `ew install ai/claude` 等细粒度选择。
func (aiModule) Components() []Component {
	return []Component{
		{Name: "claude", Description: "Anthropic Claude Code（npm: @anthropic-ai/claude-code）"},
		{Name: "codex", Description: "OpenAI Codex CLI（npm: @openai/codex）"},
		{Name: "pi", Description: "Pi coding agent（npm: @earendil-works/pi-coding-agent）"},
	}
}

// aiConfigValue 读 `[ai] <key>`，回退旧配置 `[ai_tools] <key>`。
func aiConfigValue(ctx *Context, key string) string {
	if v := ctx.Config.Get("ai."+key, ""); v != "" {
		return v
	}
	return ctx.Config.Get("ai_tools."+key, "")
}

// aiInstallEnabled 读取总开关，兼容旧 `ai_tools.install`。
func aiInstallEnabled(ctx *Context) bool {
	if ctx.Config.Get("ai.install", "") != "" {
		return ctx.Config.GetBool("ai.install", true)
	}
	if ctx.Config.Get("ai_tools.install", "") != "" {
		return ctx.Config.GetBool("ai_tools.install", true)
	}
	return true
}

// selectedTools 决定本次安装哪些子工具，优先级：
//  1. CLI 显式选择（ctx.Selected，来自 `ai/claude`，空格分隔多个参数）；
//  2. config.toml 的 `[ai] tools`（空格分隔的默认子集，兼容旧 `ai_tools.tools`）；
//  3. 全部。
func selectedTools(ctx *Context) []aiTool {
	names := ctx.Selected
	if len(names) == 0 {
		if v := aiConfigValue(ctx, "tools"); v != "" {
			names = strings.Fields(v)
		}
	}
	if len(names) == 0 {
		return aiTools
	}
	want := map[string]bool{}
	for _, n := range names {
		want[strings.TrimSpace(n)] = true
	}
	var out []aiTool
	for _, t := range aiTools {
		if want[t.cli] {
			out = append(out, t)
		}
	}
	return out
}

func toolNames(tools []aiTool) string {
	csv := ""
	for _, t := range tools {
		csv = appendCSV(csv, t.cli)
	}
	return csv
}

func (aiModule) Install(ctx *Context) error {
	tools := selectedTools(ctx)
	if len(tools) == 0 {
		ctx.Log.Warn("未选中任何 AI 工具，跳过（可用: claude, codex, pi）")
		return nil
	}
	names := toolNames(tools)

	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将安装 AI 编码 CLI: " + strings.ReplaceAll(names, ",", ", "))
		return nil
	}
	if ctx.Offline {
		ctx.Log.Warn("离线模式：跳过 AI 工具安装")
		return nil
	}
	if !aiInstallEnabled(ctx) {
		ctx.Log.Info("配置已禁用 AI 工具安装（ai.install=false）")
		return nil
	}

	installed := ""
	for _, t := range tools {
		if platform.HasCmd(t.cli) {
			ctx.Log.Info(t.cli + " 已安装")
			installed = appendCSV(installed, t.cli)
			continue
		}
		if !platform.HasCmd("npm") {
			ctx.Log.Warn("未找到 npm，跳过 " + t.cli)
			continue
		}
		if err := exec.Command("npm", "install", "-g", t.pkg).Run(); err != nil {
			ctx.Log.Warn(t.cli + " 安装失败")
			continue
		}
		installed = appendCSV(installed, t.cli)
	}
	return ctx.Manifest.SetSection("ai",
		"installed=true",
		"selected="+names,
		"tools="+installed,
	)
}

func (aiModule) Uninstall(ctx *Context) error {
	ctx.Log.Info("保留已安装的 AI 工具（不自动卸载）")
	return nil
}

func appendCSV(csv, v string) string {
	if csv == "" {
		return v
	}
	return csv + "," + v
}
