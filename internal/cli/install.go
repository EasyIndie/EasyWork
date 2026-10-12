package cli

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/EasyIndie/EasyWork/internal/modules"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// target 是一次安装目标：模块级（all）或若干显式子组件。
type target struct {
	all        bool
	components []string
}

// parseTargets 解析安装目标，**空格分隔**（每个参数一个目标，即 shell 的
// 空白分词），支持：
//
//	ai                     模块（含全部子组件）
//	ai/claude              仅 claude
//	claude                 子组件简写（全局唯一时）
//	ai/claude ai/codex     多个目标（空格分隔）
//	git ai/pi              混合多个目标
//
// 名字原样保留（不 trim），因此含空格/特殊字符的名字用引号作为单个参数传入：
//
//	ew install "ai/my tool"
//
// 逗号不再作为分隔符（它是名字的一部分）。返回的 map 键为**正式模块名**。
func parseTargets(args []string) (map[string]*target, error) {
	out := map[string]*target{}
	for _, raw := range args {
		if raw == "" {
			continue
		}
		if strings.Contains(raw, "/") {
			segs := strings.SplitN(raw, "/", 2)
			mod, comp := segs[0], segs[1]
			m, ok := modules.ByName(mod)
			if !ok {
				return nil, fmt.Errorf("未知组件: %s", raw)
			}
			if err := validateComponentName(comp); err != nil {
				return nil, fmt.Errorf("非法子工具名 %q: %v", comp, err)
			}
			if !hasComponent(m, comp) {
				return nil, fmt.Errorf("未知子工具: %s（%s 可用子工具: %s）", raw, m.Name(), componentCSV(m))
			}
			t := ensureTarget(out, m.Name())
			t.components = appendUnique(t.components, comp)
			continue
		}
		if m, ok := modules.ByName(raw); ok {
			ensureTarget(out, m.Name()).all = true
			continue
		}
		// 子组件简写：全仓库唯一则解析为其所属模块。
		if mod, ok := modules.FindComponent(raw); ok {
			t := ensureTarget(out, mod)
			t.components = appendUnique(t.components, raw)
			continue
		}
		return nil, fmt.Errorf("未知组件: %s", raw)
	}
	return out, nil
}

// validateComponentName 允许字母/数字/下划线/连字符及空格等可打印字符，
// 仅拒绝空、`/`（分隔符）与控制字符。
func validateComponentName(name string) error {
	if name == "" {
		return errors.New("不能为空")
	}
	if strings.Contains(name, "/") {
		return errors.New("不能包含 '/'")
	}
	for _, r := range name {
		if r < 0x20 || r == 0x7f {
			return errors.New("不能包含控制字符")
		}
	}
	return nil
}

func ensureTarget(m map[string]*target, mod string) *target {
	if m[mod] == nil {
		m[mod] = &target{}
	}
	return m[mod]
}

func hasComponent(m modules.Module, name string) bool {
	for _, c := range modules.Components(m) {
		if c.Name == name {
			return true
		}
	}
	return false
}

func componentCSV(m modules.Module) string {
	names := []string{}
	for _, c := range modules.Components(m) {
		names = append(names, c.Name)
	}
	return strings.Join(names, ", ")
}

func appendUnique(list []string, v string) []string {
	for _, x := range list {
		if x == v {
			return list
		}
	}
	return append(list, v)
}

// moduleContext 构造模块执行上下文。
func (a *App) moduleContext() *modules.Context {
	return &modules.Context{
		Env:      a.Env,
		Config:   a.Config,
		Manifest: a.Manifest,
		Version:  a.Version,
		Log:      a.Log,
		DryRun:   a.DryRun,
		Offline:  a.Offline,
		Yes:      a.Yes,
	}
}

// moduleState 返回模块状态，兼容历史别名节（如 ai-tools → ai）。
func (a *App) moduleState(m modules.Module) string {
	if s := a.Manifest.ModuleState(m.Name()); s != "absent" {
		return s
	}
	for _, al := range modules.Aliases(m) {
		if s := a.Manifest.ModuleState(al); s != "absent" {
			return s
		}
	}
	return "absent"
}

// sectionInstalled 报告模块节或其别名节是否已存在。
func (a *App) sectionInstalled(m modules.Module) bool {
	if a.Manifest.SectionExists(m.Name()) {
		return true
	}
	for _, al := range modules.Aliases(m) {
		if a.Manifest.SectionExists(al) {
			return true
		}
	}
	return false
}

// cmdInstall 安装全部或指定模块（契约五编排）。
// 目标语法：`module`（全部子组件）、`module/component`、`component` 简写，
// 多个目标以空格分隔。
func (a *App) cmdInstall(args []string) int {
	targets, err := parseTargets(args)
	if err != nil {
		a.Log.Info("提示: ew list 查看可用组件与子工具")
		return a.fail(1, err.Error())
	}

	if _, err := a.Config.Ensure(a.Env); err != nil {
		return a.fail(1, "创建配置失败: "+err.Error())
	}

	// 交互增强（仅 tty 且未 --yes/--json/--dry-run），全程 ≤2 问
	a.wizardGitIdentity()

	if !a.Manifest.Exists() {
		if err := a.Manifest.Init(a.Env, a.Version); err != nil {
			return a.fail(1, "初始化 manifest 失败: "+err.Error())
		}
	}

	lock, err := platform.AcquireLock(a.Env.TempDir, 30*time.Second)
	if err != nil {
		if errors.Is(err, platform.ErrLockTimeout) {
			return a.fail(5, "获取锁超时，请稍后重试")
		}
		return a.fail(1, "获取锁失败: "+err.Error())
	}
	defer lock.Release()

	osName := platform.DetectOS()
	var failed []string
	for _, m := range modules.Sorted() {
		// 可选模块默认不装（仅显式指名时安装）。
		if len(args) == 0 && modules.IsOptional(m) {
			continue
		}
		var selected []string
		if len(args) > 0 {
			t, ok := targets[m.Name()]
			if !ok {
				continue
			}
			if !t.all {
				selected = t.components
			}
		}
		if !modules.Supports(m, osName) {
			a.Log.Info("跳过 " + m.Name() + "（当前平台不支持）")
			continue
		}
		a.Log.Info("配置 " + m.Name() + "...")
		ctx := a.moduleContext()
		ctx.Selected = selected
		if err := m.Install(ctx); err != nil {
			a.Log.Error("[" + m.Name() + "] 失败: " + err.Error())
			failed = append(failed, m.Name())
			_ = a.Manifest.SetSection(m.Name(), "installed=failed", "failed_at="+nowStamp())
			continue
		}
		a.Log.Success(m.Name() + " 完成")
	}

	if a.Manifest.Exists() {
		_ = a.Manifest.SetTop("easywork_version", a.Version)
	}

	// 配置 shell 补全（与 Bash 实现一致，安装后自动注入）
	a.setupCompletions()

	if len(failed) > 0 {
		return a.fail(1, "以下组件安装失败: "+join(failed, " "))
	}
	a.Log.Success("EasyWork " + a.Version + " 安装完成 🎉")
	return 0
}

// cmdUninstall 卸载指定或全部已安装模块。
func (a *App) cmdUninstall(args []string) int {
	if !a.Manifest.Exists() {
		return a.fail(1, "未检测到安装记录（"+a.Manifest.Path()+" 不存在）")
	}
	lock, err := platform.AcquireLock(a.Env.TempDir, 30*time.Second)
	if err != nil {
		if errors.Is(err, platform.ErrLockTimeout) {
			return a.fail(5, "获取锁超时，请稍后重试")
		}
		return a.fail(1, "获取锁失败: "+err.Error())
	}
	defer lock.Release()

	var targets []string
	if len(args) > 0 {
		// 接受 `module/component` 语法（子组件粒度卸载 → 归到所属模块）。
		name := args[0]
		if i := strings.Index(name, "/"); i >= 0 {
			name = name[:i]
		}
		m, ok := modules.ByName(name)
		if !ok {
			return a.fail(1, "未知组件: "+name)
		}
		if !a.sectionInstalled(m) {
			return a.fail(1, "组件 '"+m.Name()+"' 未安装")
		}
		targets = []string{m.Name()}
	} else {
		targets = a.Manifest.ListInstalled()
		for i, t := range targets {
			targets[i] = modules.Canonical(t)
		}
	}

	for _, t := range targets {
		m, ok := modules.ByName(t)
		if !ok {
			_ = a.Manifest.RemoveSection(t)
			continue
		}
		a.Log.Info("[" + t + "] 卸载中...")
		if err := m.Uninstall(a.moduleContext()); err != nil {
			a.Log.Warn("[" + t + "] 卸载时出现警告: " + err.Error())
		} else {
			a.Log.Success("[" + t + "] 已卸载")
		}
		_ = a.Manifest.RemoveSection(m.Name())
		for _, al := range modules.Aliases(m) {
			_ = a.Manifest.RemoveSection(al)
		}
	}

	if a.RemoveConfig {
		_ = os.Remove(a.Config.Path())
		a.Log.Info("已删除配置文件")
	}
	return 0
}

func join(list []string, sep string) string {
	out := ""
	for i, x := range list {
		if i > 0 {
			out += sep
		}
		out += x
	}
	return out
}
