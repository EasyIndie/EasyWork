package modules

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

type ghModule struct{}

func (ghModule) Name() string             { return "gh" }
func (ghModule) Description() string      { return "安装 GitHub CLI (gh)" }
func (ghModule) Priority() int            { return 25 }
func (ghModule) Platforms() []platform.OS { return allPlatforms() }

// ─── GitHub 官方源（旧发行版默认源缺少 gh 时使用） ───────────
// 变量而非常量：便于测试注入本地 httptest 源。
var (
	ghKeyringURL = "https://cli.github.com/packages/githubcli-archive-keyring.gpg"
	ghAptRepoURI = "https://cli.github.com/packages"
	ghDnfRepoURL = "https://cli.github.com/packages/rpm/gh-cli.repo"
)

// ghAptRepoLine 生成 GitHub 官方 apt 源条目。
func ghAptRepoLine(arch, keyring string) string {
	return "deb [arch=" + arch + " signed-by=" + keyring + "] " + ghAptRepoURI + " stable main"
}

// ghInstallStrategy 决定安装策略：apt / dnf / 默认（brew/winget/…）。
func ghInstallStrategy(pm string) string {
	switch pm {
	case "apt-get":
		return "apt"
	case "dnf", "yum":
		return "dnf"
	default:
		return "default"
	}
}

// installGitHubCLI 安装 gh：优先默认源，旧发行版回退官方源。
func installGitHubCLI(ctx *Context, pm platform.PackageManager) error {
	switch ghInstallStrategy(pm.Name()) {
	case "apt":
		return installGHApt(ctx)
	case "dnf":
		return installGHDnf(ctx, pm.Name())
	default:
		return pm.Install("gh")
	}
}

func installGHApt(ctx *Context) error {
	if sudoOK("apt-get", "update", "-y") && sudoOK("apt-get", "install", "-y", "gh") {
		return nil
	}
	ctx.Log.Info("默认 apt 源未提供 gh，添加 GitHub 官方 apt 源...")
	if err := setupGHAptRepo(ctx); err != nil {
		return err
	}
	return sudo("apt-get", "install", "-y", "gh")
}

func setupGHAptRepo(ctx *Context) error {
	keyring := "/etc/apt/keyrings/githubcli-archive-keyring.gpg"
	if err := sudo("mkdir", "-p", "-m", "755", "/etc/apt/keyrings"); err != nil {
		return err
	}
	tmp := filepath.Join(ctx.Env.TempDir, "gh-keyring.gpg")
	if err := platform.Download(ghKeyringURL, tmp); err != nil {
		return err
	}
	if err := sudo("cp", tmp, keyring); err != nil {
		return err
	}
	_ = sudo("chmod", "go+r", keyring)

	arch := strings.TrimSpace(capture("dpkg", "--print-architecture"))
	if arch == "" {
		arch = "amd64"
	}
	listFile := filepath.Join(ctx.Env.TempDir, "github-cli.list")
	if err := os.WriteFile(listFile, []byte(ghAptRepoLine(arch, keyring)+"\n"), 0o644); err != nil {
		return err
	}
	if err := sudo("cp", listFile, "/etc/apt/sources.list.d/github-cli.list"); err != nil {
		return err
	}
	_ = sudo("apt-get", "update", "-y")
	return nil
}

func installGHDnf(ctx *Context, mgr string) error {
	if sudoOK(mgr, "install", "-y", "gh") {
		return nil
	}
	ctx.Log.Info("默认 " + mgr + " 源未提供 gh，添加 GitHub 官方 dnf 源...")
	if err := setupGHDnfRepo(ctx, mgr); err != nil {
		return err
	}
	return sudo(mgr, "install", "-y", "gh", "--repo", "gh-cli")
}

func setupGHDnfRepo(_ *Context, mgr string) error {
	_ = sudo(mgr, "install", "-y", "dnf-command(config-manager)")
	// dnf4/yum 语法，其次 dnf5 语法
	if sudoOK(mgr, "config-manager", "--add-repo", ghDnfRepoURL) {
		return nil
	}
	return sudo(mgr, "config-manager", "addrepo", "--from-repofile="+ghDnfRepoURL)
}

// ─── sudo/exec 辅助 ──────────────────────────────────────────
func sudo(name string, args ...string) error {
	if platform.HasCmd("sudo") {
		return exec.Command("sudo", append([]string{name}, args...)...).Run()
	}
	return exec.Command(name, args...).Run()
}

func sudoOK(name string, args ...string) bool { return sudo(name, args...) == nil }

func capture(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return string(out)
}

func (ghModule) Install(ctx *Context) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将安装 GitHub CLI (gh)")
		return nil
	}
	if platform.HasCmd("gh") {
		ctx.Log.Info("gh 已安装")
		return ctx.Manifest.SetSection("gh", "installed=true")
	}
	if ctx.Offline {
		ctx.Log.Warn("离线模式：跳过 gh 安装")
		return nil
	}
	pm := platform.DetectPackageManager()
	if !pm.Known() {
		ctx.Log.Warn("未识别的包管理器，请手动安装 gh: https://cli.github.com/")
		return ctx.Manifest.SetSection("gh", "installed=true")
	}
	ctx.Log.Info("使用 " + pm.Name() + " 安装 gh...")
	if err := installGitHubCLI(ctx, pm); err != nil {
		return err
	}
	if !platform.HasCmd("gh") {
		ctx.Log.Warn("gh 安装后仍未在 PATH 中找到，请检查 PATH")
		return ctx.Manifest.SetSection("gh", "installed=true")
	}
	return ctx.Manifest.SetSection("gh", "installed=true")
}

func (ghModule) Uninstall(ctx *Context) error {
	ctx.Log.Info("保留已安装的 GitHub CLI（不自动卸载）")
	return nil
}
