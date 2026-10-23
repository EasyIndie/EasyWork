package modules

import (
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

type gitModule struct{}

func (gitModule) Name() string             { return "git" }
func (gitModule) Description() string      { return "配置 Git 别名和身份" }
func (gitModule) Priority() int            { return 20 }
func (gitModule) Platforms() []platform.OS { return allPlatforms() }

// resolveGitIdentity 按「config.toml → 已有 git config --global → 空」探测身份，
// 身份零配置可用：缺失不阻塞安装。
func resolveGitIdentity(ctx *Context) (name, email string) {
	identity := ctx.Config.Get("git.identity", "personal")
	name = ctx.Config.Get("git.identities."+identity+".name", "")
	email = ctx.Config.Get("git.identities."+identity+".email", "")
	if name == "" {
		name = ctx.Config.Get("git.identities.personal.name", "")
	}
	if email == "" {
		email = ctx.Config.Get("git.identities.personal.email", "")
	}
	if name == "" {
		name = gitGlobalValue("user.name")
	}
	if email == "" {
		email = gitGlobalValue("user.email")
	}
	return name, email
}

func gitGlobalValue(key string) string {
	out, err := exec.Command("git", "config", "--global", key).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// gitConfigContent 生成 ~/.gitconfig 的 managed section 内容。
// 有完整身份时前置 [user]；否则仅别名（保持历史行为不变）。
func gitConfigContent(ctx *Context) string {
	name, email := resolveGitIdentity(ctx)
	if name != "" && email != "" {
		return fmt.Sprintf("[user]\n    name = %s\n    email = %s\n\n%s", name, email, gitAliasConfig)
	}
	return gitAliasConfig
}

func (gitModule) Install(ctx *Context) error {
	if !platform.HasCmd("git") {
		return errors.New("Git 未安装")
	}

	scope := ctx.Config.Get("git.scope", "global")
	name, email := resolveGitIdentity(ctx)

	// 仓库级：直接写 --local 身份（无可写内容时跳过）。
	if scope == "local" {
		if name == "" {
			ctx.Log.Info("未检测到 Git 身份，跳过仓库级配置")
			return nil
		}
		if ctx.DryRun {
			ctx.Log.Info("[DRY-RUN] 将设置仓库级 Git 身份: " + name)
			return nil
		}
		if err := exec.Command("git", "config", "--local", "user.name", name).Run(); err != nil {
			return err
		}
		if err := exec.Command("git", "config", "--local", "user.email", email).Run(); err != nil {
			return err
		}
		repo, _ := exec.Command("git", "rev-parse", "--show-toplevel").Output()
		return ctx.Manifest.SetSection("git",
			"installed=true",
			"scope=local",
			"repo="+strings.TrimSpace(string(repo)),
		)
	}

	// 全局：managed section（别名 + 可选身份）。
	target := filepath.Join(ctx.Env.Home, ".gitconfig")
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将写入 Git 配置: " + target)
		return nil
	}
	backup, err := engine.ApplyManagedSection(target, ctx.Version, gitConfigContent(ctx), "#")
	if err != nil {
		return err
	}
	pairs := []string{
		"installed=true",
		"scope=global",
		"config_file=" + target,
	}
	if backup != "" {
		pairs = append(pairs, "config_backup="+backup)
	}
	if name != "" && email != "" {
		pairs = append(pairs, "display_name=git ("+name+")")
	}
	return ctx.Manifest.SetSection("git", pairs...)
}

func (gitModule) Uninstall(ctx *Context) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将移除 Git 配置")
		return nil
	}
	scope := ctx.Manifest.ReadSectionKey("git", "scope", "global")
	if scope == "local" {
		_ = exec.Command("git", "config", "--local", "--unset", "user.name").Run()
		_ = exec.Command("git", "config", "--local", "--unset", "user.email").Run()
		return nil
	}
	target := filepath.Join(ctx.Env.Home, ".gitconfig")
	backup := ctx.Manifest.ReadSectionKey("git", "config_backup", "")
	return engine.RemoveFile(target, backup)
}
