package modules

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

type shellModule struct{}

func (shellModule) Name() string        { return "shell" }
func (shellModule) Description() string { return "配置 Shell 环境 (bash/zsh 适配)" }
func (shellModule) Priority() int       { return 10 }
func (shellModule) Platforms() []platform.OS {
	return allPlatforms()
}

func shellConfigContent(ctx *Context) string {
	var b strings.Builder
	b.WriteString("\n")
	b.WriteString("export LC_ALL=en_US.UTF-8\n")
	b.WriteString("export LANG=en_US.UTF-8\n")
	if ctx.Config.GetBool("shell.enable_aliases", true) {
		b.WriteString(`
# 安全别名
alias g='git'
alias q='exit'
alias grep='grep --color=auto'
alias mv='mv -i'
alias cp='cp -i'
alias rm='rm -i'
`)
	}
	if ctx.Config.GetBool("shell.enable_fancy_prompt", false) {
		b.WriteString(`
# 简化提示符（含 Git 分支）
__ew_git_branch() { git branch 2>/dev/null | sed -n 's/^\* //p'; }
PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[33m\]$(__ew_git_branch)\[\e[0m\]\$ '
`)
	}
	b.WriteString("\n")
	b.WriteString("# 系统信息\n")
	b.WriteString("sys_info() {\n")
	b.WriteString("    uname -a\n")
	b.WriteString("}\n")
	return strings.TrimRight(b.String(), "\n")
}

func (shellModule) Install(ctx *Context) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将写入 Shell 配置")
		return nil
	}

	// Windows：直接向 PowerShell profile 注入 managed section（无 source 间接层）。
	if platform.DetectOS() == platform.Windows {
		target := ctx.Env.PowerShellProfile()
		if _, err := engine.ApplyManagedSection(target, ctx.Version, powerShellConfigContent(ctx), "#"); err != nil {
			return err
		}
		return ctx.Manifest.SetSection("shell",
			"installed=true",
			"shell_type=pwsh",
			"display_name=shell (pwsh)",
			"source_file="+target,
			"config_created="+target,
		)
	}

	target := filepath.Join(ctx.Env.Home, ".sh_config_custom")
	if _, err := engine.ApplyManagedSection(target, ctx.Version, shellConfigContent(ctx), "#"); err != nil {
		return err
	}

	rc := ctx.Env.ShellRC()
	if err := injectSourceLine(rc, target); err != nil {
		return err
	}

	return ctx.Manifest.SetSection("shell",
		"installed=true",
		"shell_type="+platform.DetectShell(),
		"display_name=shell ("+platform.DetectShell()+")",
		"source_file="+rc,
		"config_created="+target,
	)
}

func (shellModule) Uninstall(ctx *Context) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将移除 Shell 配置")
		return nil
	}
	if platform.DetectOS() == platform.Windows {
		return engine.RemoveManagedSection(ctx.Env.PowerShellProfile())
	}
	target := filepath.Join(ctx.Env.Home, ".sh_config_custom")
	if err := engine.RemoveManagedSection(target); err != nil {
		return err
	}
	rc := ctx.Env.ShellRC()
	_ = removeSourceLine(rc, target)
	return nil
}

// powerShellConfigContent 生成 Windows PowerShell profile 的 managed 内容。
func powerShellConfigContent(ctx *Context) string {
	var b strings.Builder
	b.WriteString("\n# EasyWork PowerShell 环境\n")
	if ctx.Config.GetBool("shell.enable_aliases", true) {
		b.WriteString("Set-Alias -Name g -Value git -Force\n")
		b.WriteString("Set-Alias -Name grep -Value Select-String -Force\n")
		b.WriteString("function q { exit }\n")
	}
	return strings.TrimRight(b.String(), "\n")
}

// injectSourceLine 幂等注入 `source <target>` 到 rc 文件。
func injectSourceLine(rc, target string) error {
	line := "source " + target + "  # EasyWork shell config"
	data, err := os.ReadFile(rc)
	if err == nil {
		if strings.Contains(string(data), "source "+target) {
			return nil
		}
		content := string(data)
		if content != "" && !strings.HasSuffix(content, "\n") {
			content += "\n"
		}
		content += "\n" + line + "\n"
		return platform.AtomicWrite(rc, []byte(content), 0o644)
	}
	return platform.AtomicWrite(rc, []byte(line+"\n"), 0o644)
}

// removeSourceLine 移除 EasyWork 注入的 source 行。
func removeSourceLine(rc, target string) error {
	data, err := os.ReadFile(rc)
	if err != nil {
		return nil
	}
	needle := "source " + target
	var out []string
	for _, l := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		if strings.Contains(l, needle) {
			continue
		}
		out = append(out, l)
	}
	for len(out) > 0 && strings.TrimSpace(out[len(out)-1]) == "" {
		out = out[:len(out)-1]
	}
	content := ""
	if len(out) > 0 {
		content = strings.Join(out, "\n") + "\n"
	}
	return platform.AtomicWrite(rc, []byte(content), 0o644)
}
