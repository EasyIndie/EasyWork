// Package modules 定义模块接口、注册表与各内置模块（契约五）。
package modules

import (
	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/logx"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// Context 是模块执行时可见的上下文。
type Context struct {
	Env      platform.Env
	Config   engine.Config
	Manifest engine.Manifest
	Version  string
	Log      *logx.Logger

	DryRun  bool
	Offline bool
	Yes     bool

	// Selected 是本模块被显式选中的子组件名（CLI 语法 module/component）。
	// 为空表示「未做子组件选择」= 全部（模块可再用 config 默认值收窄）。
	Selected []string
}

// ComponentSelected 报告某子组件是否被选中（未指定选择时视为全选）。
func (c *Context) ComponentSelected(name string) bool {
	if len(c.Selected) == 0 {
		return true
	}
	for _, s := range c.Selected {
		if s == name {
			return true
		}
	}
	return false
}

// Component 是模块内部的细粒度选装项（子工具）。
type Component struct {
	Name        string
	Description string
}

// ComponentModule 是可选接口：模块声明子组件后即可被细粒度选择。
type ComponentModule interface {
	Module
	Components() []Component
}

// Aliased 是可选接口：模块声明历史/兼容别名（如 ai-tools → ai）。
type Aliased interface {
	Module
	Aliases() []string
}

// Aliases 返回模块的兼容别名（未声明则 nil）。
func Aliases(m Module) []string {
	if a, ok := m.(Aliased); ok {
		return a.Aliases()
	}
	return nil
}

// OptionalModule 是可选的：标记「可选」的模块默认不在 `ew install`（无参数）
// 中安装，只有显式 `ew install <module>` 才安装。
type OptionalModule interface {
	Module
	Optional() bool
}

// IsOptional 报告模块是否为可选（默认 false）。
func IsOptional(m Module) bool {
	if o, ok := m.(OptionalModule); ok {
		return o.Optional()
	}
	return false
}

// Components 返回模块子组件（未声明则 nil）。
func Components(m Module) []Component {
	if cm, ok := m.(ComponentModule); ok {
		return cm.Components()
	}
	return nil
}

// FindComponent 在全部模块中查找唯一同名子组件，返回其所属模块名。
// 用于 `ew install <component>` 简写（如 `ew install claude`）。
func FindComponent(name string) (string, bool) {
	var owner string
	found := false
	for _, m := range registry {
		for _, c := range Components(m) {
			if c.Name == name {
				if found {
					return "", false // 跨模块重名 → 不消歧，要求写全 module/component
				}
				owner = m.Name()
				found = true
			}
		}
	}
	return owner, found
}

// Module 是语言无关的模块接口（契约五）。
type Module interface {
	Name() string
	Description() string
	Priority() int
	Platforms() []platform.OS
	Install(ctx *Context) error
	Uninstall(ctx *Context) error
}

// Supports 判断模块是否支持当前平台。
func Supports(m Module, os platform.OS) bool {
	ps := m.Platforms()
	if len(ps) == 0 {
		return true
	}
	for _, p := range ps {
		if p == os {
			return true
		}
	}
	return false
}

// allPlatforms 是“全平台”的便捷返回。
func allPlatforms() []platform.OS {
	return []platform.OS{platform.MacOS, platform.Linux, platform.Windows}
}

// registry 的**顺序必须**与 Bash `_discover_modules` 扫描 lib/*.sh 的字母序一致，
// 因为 list --json 直接按注册顺序输出。
var registry = []Module{
	aiModule{},        // ai（别名 ai-tools）
	ghModule{},        // gh
	ghosttyModule{},   // ghostty（可选，终端模拟器）
	gitModule{},       // git
	glowModule{},      // glow（可选，CLI）
	herdrModule{},     // herdr（可选，CLI）
	keepawakeModule{}, // keepawake（可选，设备防休眠）
	moleModule{},      // mole（可选，CLI）
	shellModule{},     // shell
	vimModule{},       // vim
}

// All 返回按注册顺序排列的模块。
func All() []Module { return registry }

// ByName 按名字或兼容别名查找模块。
func ByName(name string) (Module, bool) {
	for _, m := range registry {
		if m.Name() == name {
			return m, true
		}
	}
	for _, m := range registry {
		for _, a := range Aliases(m) {
			if a == name {
				return m, true
			}
		}
	}
	return nil, false
}

// Canonical 把模块别名归一为正式名（未知名字原样返回）。
func Canonical(name string) string {
	if m, ok := ByName(name); ok {
		return m.Name()
	}
	return name
}

// Sorted 返回按 priority 升序（同优先级保持注册顺序）的模块。
func Sorted() []Module {
	out := make([]Module, len(registry))
	copy(out, registry)
	// 稳定的插入排序，避免引入 sort 依赖之外的复杂度
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && out[j-1].Priority() > out[j].Priority(); j-- {
			out[j-1], out[j] = out[j], out[j-1]
		}
	}
	return out
}
