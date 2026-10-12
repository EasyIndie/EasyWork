// Package platform 隔离各操作系统的差异（契约一：状态根与路径）。
package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// OS 表示受支持的平台。
type OS string

const (
	MacOS   OS = "macos"
	Linux   OS = "linux"
	Windows OS = "windows"
	Unknown OS = "unknown"
)

// DetectOS 返回当前平台。
func DetectOS() OS {
	switch runtime.GOOS {
	case "darwin":
		return MacOS
	case "linux":
		return Linux
	case "windows":
		return Windows
	default:
		return Unknown
	}
}

// Env 描述一次运行的环境：状态根、主目录与临时目录。
type Env struct {
	Home         string // 模块目标文件根（HOME / USERPROFILE）
	EasyworkHome string // 工具状态根（契约一）
	TempDir      string
}

// NewEnv 依据环境变量解析出 Env。
// EASYWORK_HOME 优先；否则 ${HOME}/.easywork；HOME 缺失时用用户主目录（Windows）。
func NewEnv() Env {
	home := os.Getenv("HOME")
	if home == "" {
		home, _ = os.UserHomeDir()
	}
	ewHome := os.Getenv("EASYWORK_HOME")
	if ewHome == "" {
		ewHome = filepath.Join(home, ".easywork")
	}
	tmp := os.Getenv("TMPDIR")
	if tmp == "" {
		tmp = os.TempDir()
	}
	return Env{Home: home, EasyworkHome: ewHome, TempDir: tmp}
}

// ConfigPath 返回 config.toml 路径（契约二）。
func (e Env) ConfigPath() string { return filepath.Join(e.EasyworkHome, "config.toml") }

// LegacyConfigPath 返回旧 ini 配置路径。
func (e Env) LegacyConfigPath() string { return filepath.Join(e.EasyworkHome, "config") }

// ManifestPath 返回 manifest 路径（契约三）。
func (e Env) ManifestPath() string { return filepath.Join(e.EasyworkHome, "manifest") }

// UpdateCachePath 返回更新检查缓存路径。
func (e Env) UpdateCachePath() string { return filepath.Join(e.EasyworkHome, ".last_update_check") }

// CompletionsDir 返回 shell 补全文件目录。
func (e Env) CompletionsDir() string { return filepath.Join(e.EasyworkHome, "completions") }

// LibCacheDir 返回管道模式库缓存目录。
func (e Env) LibCacheDir(version string) string {
	return filepath.Join(e.EasyworkHome, "lib", "v"+version)
}

// EnsureHome 创建状态根目录。
func (e Env) EnsureHome() error { return os.MkdirAll(e.EasyworkHome, 0o755) }

// PathList 返回 PATH 的分隔列表（用于 LookPath 兼容提示）。
func PathList() []string { return strings.Split(os.Getenv("PATH"), string(os.PathListSeparator)) }
