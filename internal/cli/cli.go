// Package cli 实现 CLI 路由与各命令（契约四）。
package cli

import (
	"os"
	"path/filepath"
	"time"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/modules"
	"github.com/EasyIndie/EasyWork/internal/platform"
	"github.com/EasyIndie/EasyWork/internal/version"
)

// App 持有一次运行的全局状态。
type App struct {
	Env      platform.Env
	Config   engine.Config
	Manifest engine.Manifest
	Log      *logx.Logger
	Version  string
	Channel  string

	JSON         bool
	DryRun       bool
	Yes          bool
	Verbose      bool
	Offline      bool
	KeepConfig   bool
	RemoveConfig bool

	command string // 当前命令（用于错误信封的 command 字段）
}

// New 构造 App（读取环境与版本）。
func New() *App {
	env := platform.NewEnv()
	channel := os.Getenv("EASYWORK_CHANNEL")
	if channel == "" && detectDev() {
		channel = "dev"
	}
	log := logx.New()
	return &App{
		Env:      env,
		Config:   engine.NewConfig(env),
		Manifest: engine.NewManifest(env),
		Log:      log,
		Version:  version.Version,
		Channel:  channel,
	}
}

func detectDev() bool {
	dir := ""
	if exe, err := os.Executable(); err == nil {
		if resolved, e := filepath.EvalSymlinks(exe); e == nil {
			dir = filepath.Dir(resolved)
		} else {
			dir = filepath.Dir(exe)
		}
	}
	if dir == "" {
		dir, _ = os.Getwd()
	}
	for dir != "" {
		if _, statErr := os.Stat(filepath.Join(dir, ".git")); statErr == nil {
			return true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return false
		}
		dir = parent
	}
	return false
}

// parseFlags 从参数流中提取全局 flag，返回剩余参数。
func (a *App) parseFlags(args []string) []string {
	var rest []string
	for _, arg := range args {
		switch arg {
		case "--json":
			a.JSON = true
		case "--dry-run":
			a.DryRun = true
		case "--yes", "-y":
			a.Yes = true
		case "--verbose", "-v":
			a.Verbose = true
		case "--offline":
			a.Offline = true
		case "--keep-config":
			a.KeepConfig = true
		case "--remove-config":
			a.RemoveConfig = true
		default:
			rest = append(rest, arg)
		}
	}
	a.Log.JSON = a.JSON
	a.Log.Verbose = a.Verbose
	return rest
}

// Run 解析参数并执行命令，返回退出码。
func Run(args []string) int {
	app := New()
	cleanupStaleBinary()
	rest := app.parseFlags(args)
	return app.Dispatch(rest)
}

// cleanupStaleBinary 尽力删除上次自升级遗留的 <exe>.old（Windows 上运行中的镜像无法删除）。
func cleanupStaleBinary() {
	exe, err := os.Executable()
	if err != nil {
		return
	}
	if resolved, e := filepath.EvalSymlinks(exe); e == nil {
		exe = resolved
	}
	_ = os.Remove(exe + ".old")
}

// Dispatch 按子命令分发。
func (a *App) Dispatch(args []string) int {
	cmd := ""
	if len(args) > 0 {
		cmd = args[0]
	}
	a.command = cmd
	rest := args
	if cmd != "" {
		rest = args[1:]
	}

	switch cmd {
	case "status":
		return a.cmdStatus()
	case "list":
		return a.cmdList()
	case "version":
		return a.cmdVersion()
	case "doctor":
		return a.cmdDoctor()
	case "config":
		return a.cmdConfig(rest)
	case "install":
		return a.cmdInstall(rest)
	case "uninstall":
		return a.cmdUninstall(rest)
	case "init":
		a.Yes = true
		return a.cmdInstall([]string{"shell", "git"})
	case "update":
		return a.cmdUpdate()
	case "help", "--help", "-h", "":
		a.printHelp()
		return 0
	case "completion", "comp":
		return a.cmdCompletion(rest)
	default:
		if _, ok := modules.ByName(cmd); ok {
			a.Log.Info("请使用: ew install " + cmd)
			return a.fail(1, "不支持模块快捷命令: "+cmd)
		}
		a.printHelp()
		return a.fail(1, "未知命令: "+cmd)
	}
}

func (a *App) printHelp() {
	out := a.Log.Out
	if a.JSON {
		out = a.Log.Err
	}
	text := `EasyWork — 开发环境配置

用法: ew <命令> [参数] [选项]

命令:
  init                  轻量初始化（shell + git，零交互）
  install [组件...]     安装全部组件（或指定组件）
  uninstall [组件...]   卸载组件
  status                查看当前状态（默认命令）
  doctor                环境诊断
  list                  列出可用组件
  config get/set/edit   配置管理
  version               查看版本
  version / update      查看与升级
  help                  帮助

选项:
  --json                机器可读 JSON（日志走 stderr）
  --dry-run             预览变更
  --yes, -y             跳过确认
  --verbose, -v         详细输出
  --offline             禁止联网
  --keep-config         卸载保留配置
  --remove-config       卸载删除配置
`
	_, _ = out.Write([]byte(text))
}

// nowStamp 返回 ISO8601（带时区偏移）。
func nowStamp() string { return time.Now().Format("2006-01-02T15:04:05-0700") }
