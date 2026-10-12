package platform

import (
	"os/exec"
)

// PackageManager 抽象各平台的包管理器（DESIGN §12.3）。
type PackageManager struct {
	name string
}

// Name 返回包管理器标识（未知时为 "unknown"）。
func (p PackageManager) Name() string { return p.name }

// Known 表示是否识别到包管理器。
func (p PackageManager) Known() bool { return p.name != "unknown" }

// DetectPackageManager 按优先级探测：macOS 用 brew，Windows 用 winget/scoop/choco，
// Linux 用 apt/dnf/yum/pacman/zypper/apk。
func DetectPackageManager() PackageManager {
	candidates := []string{"brew", "winget", "scoop", "choco", "apt-get", "dnf", "yum", "pacman", "zypper", "apk"}
	if DetectOS() == MacOS {
		candidates = append([]string{"brew"}, candidates...)
	}
	for _, c := range candidates {
		if _, err := exec.LookPath(c); err == nil {
			return PackageManager{name: c}
		}
	}
	return PackageManager{name: "unknown"}
}

// PackageName 把逻辑包名映射到各包管理器的实际包 ID。
func (p PackageManager) PackageName(logical string) string {
	switch logical {
	case "gh":
		switch p.name {
		case "winget":
			return "GitHub.cli"
		case "choco":
			return "gh"
		case "scoop":
			return "gh"
		}
	case "ripgrep":
		switch p.name {
		case "winget":
			return "BurntSushi.ripgrep.MSVC"
		case "choco":
			return "ripgrep"
		case "scoop":
			return "ripgrep"
		}
	case "node":
		switch p.name {
		case "winget":
			return "OpenJS.NodeJS.LTS"
		}
	case "glow":
		switch p.name {
		case "winget":
			return "charmbracelet.glow"
		}
	}
	return logical
}

// Install 使用探测到的包管理器安装软件包（传入逻辑名，内部映射为平台包 ID）。
func (p PackageManager) Install(pkg string) error {
	pkg = p.PackageName(pkg)
	switch p.name {
	case "brew":
		return run("brew", "install", pkg)
	case "winget":
		return run("winget", "install", "--accept-source-agreements", "--accept-package-agreements", pkg)
	case "scoop":
		return run("scoop", "install", pkg)
	case "choco":
		return run("choco", "install", "-y", pkg)
	case "apt-get":
		return runSudo("apt-get", "install", "-y", pkg)
	case "dnf":
		return runSudo("dnf", "install", "-y", pkg)
	case "yum":
		return runSudo("yum", "install", "-y", pkg)
	case "pacman":
		return runSudo("pacman", "-S", "--noconfirm", pkg)
	case "zypper":
		return runSudo("zypper", "install", "-y", pkg)
	case "apk":
		return runSudo("apk", "add", pkg)
	default:
		return errUnknownPM
	}
}

// InstallCask 用 brew --cask 安装（终端模拟器等以 cask 分发）；非 brew 时退回 Install。
func (p PackageManager) InstallCask(pkg string) error {
	if p.name == "brew" {
		return run("brew", "install", "--cask", pkg)
	}
	return p.Install(pkg)
}

func run(name string, args ...string) error {
	return exec.Command(name, args...).Run()
}

func runSudo(name string, args ...string) error {
	if _, err := exec.LookPath("sudo"); err == nil {
		return exec.Command("sudo", append([]string{name}, args...)...).Run()
	}
	return run(name, args...)
}
