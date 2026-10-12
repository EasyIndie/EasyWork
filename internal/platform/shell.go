package platform

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

var errUnknownPM = errors.New("easywork: 未识别的包管理器")

// HasCmd 判断命令是否可用（跨平台，处理 Windows PATHEXT）。
func HasCmd(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// CmdPath 返回命令的绝对路径，找不到返回空串。
func CmdPath(name string) string {
	p, err := exec.LookPath(name)
	if err != nil {
		return ""
	}
	return p
}

// ShellRC 返回 Unix 上应注入 source 行的 rc 文件（契约四/六）。
func (e Env) ShellRC() string {
	shell := filepath.Base(shellEnv())
	if DetectOS() == Windows {
		return e.PowerShellProfile()
	}
	if shell == "zsh" {
		return filepath.Join(e.Home, ".zshrc")
	}
	if DetectOS() == MacOS && shell == "bash" {
		return filepath.Join(e.Home, ".bash_profile")
	}
	return filepath.Join(e.Home, ".bashrc")
}

// PowerShellProfile 返回 Windows PowerShell 的 CurrentUserAllHosts profile 路径。
func (e Env) PowerShellProfile() string {
	docs := filepath.Join(e.Home, "Documents")
	ps7 := filepath.Join(docs, "PowerShell", "Microsoft.PowerShell_profile.ps1")
	if _, err := os.Stat(filepath.Dir(ps7)); err == nil {
		return ps7
	}
	return filepath.Join(docs, "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1")
}

// DetectShell 返回当前 shell 名。
func DetectShell() string { return filepath.Base(shellEnv()) }

func shellEnv() string {
	if s := os.Getenv("SHELL"); s != "" {
		return s
	}
	if DetectOS() == Windows {
		if s := os.Getenv("COMSPEC"); s != "" {
			return s
		}
	}
	return "/bin/bash"
}

// ToSlash 统一为 / 分隔（仅用于比较/展示）。
func ToSlash(p string) string { return strings.ReplaceAll(p, "\\", "/") }

// VimConfigPath 返回 Vim 主配置路径。
// Windows 约定为 $HOME/_vimrc；Unix 为 $HOME/.vimrc。
func (e Env) VimConfigPath() string {
	if DetectOS() == Windows {
		return filepath.Join(e.Home, "_vimrc")
	}
	return filepath.Join(e.Home, ".vimrc")
}

// VimPluginDir 返回 Vim 运行时目录（插件/autoload/undo）。
// Windows 约定为 $HOME/vimfiles；Unix 为 $HOME/.vim。
func (e Env) VimPluginDir() string {
	if DetectOS() == Windows {
		return filepath.Join(e.Home, "vimfiles")
	}
	return filepath.Join(e.Home, ".vim")
}

// VimPlugPath 返回 vim-plug 的安装路径。
func (e Env) VimPlugPath() string {
	return filepath.Join(e.VimPluginDir(), "autoload", "plug.vim")
}
