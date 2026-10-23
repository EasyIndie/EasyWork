package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/modules"
	"github.com/EasyIndie/EasyWork/internal/platform"
	"github.com/EasyIndie/EasyWork/internal/version"
)

// ─── JSON 类型（字段顺序即输出顺序，契约四） ────────────────────

type envelope struct {
	OK      bool   `json:"ok"`
	Command string `json:"command"`
	Data    any    `json:"data"`
	Error   any    `json:"error"`
}

type updateInfo struct {
	Latest    *string `json:"latest"`
	Available bool    `json:"available"`
}

type configInfo struct {
	Path   string `json:"path"`
	Exists bool   `json:"exists"`
	Valid  bool   `json:"valid"`
}

type moduleStatus struct {
	Name  string `json:"name"`
	State string `json:"state"`
	OK    bool   `json:"ok"`
}

type statusData struct {
	Config  configInfo     `json:"config"`
	Modules []moduleStatus `json:"modules"`
	Update  updateInfo     `json:"update"`
}

type listComponent struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type listModule struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Priority    int             `json:"priority"`
	Optional    bool            `json:"optional,omitempty"`
	Components  []listComponent `json:"components,omitempty"`
}

type listData struct {
	Modules []listModule `json:"modules"`
	Update  updateInfo   `json:"update"`
}

type versionData struct {
	Version     string     `json:"version"`
	Channel     string     `json:"channel"`
	InstallDate string     `json:"install_date"`
	Installed   []string   `json:"installed"`
	Update      updateInfo `json:"update"`
}

type checkItem struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Detail string `json:"detail"`
}

type doctorData struct {
	Checks []checkItem `json:"checks"`
	Update updateInfo  `json:"update"`
}

type jsonError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// fail 统一失败出口：--json 时输出错误信封到 stdout，同时日志走 stderr。
func (a *App) fail(code int, message string) int {
	if a.JSON {
		b := engine.Encode(envelope{OK: false, Command: a.command, Data: nil, Error: jsonError{Code: code, Message: message}})
		_, _ = a.Log.Out.Write(b)
	}
	a.Log.Error(message)
	return code
}

func (a *App) emit(command string, data any) {
	b := engine.Encode(envelope{OK: true, Command: command, Data: data, Error: nil})
	_, _ = a.Log.Out.Write(b)
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// ─── status ───────────────────────────────────────────────────

func (a *App) cmdStatus() int {
	exists := fileExists(a.Config.Path())
	valid := true
	if exists {
		valid = a.Config.Valid()
	}
	mods := make([]moduleStatus, 0, len(modules.All()))
	for _, m := range modules.Sorted() {
		state := a.moduleState(m)
		mods = append(mods, moduleStatus{Name: m.Name(), State: state, OK: state == "true"})
	}
	data := statusData{
		Config:  configInfo{Path: platform.ToSlash(a.Config.Path()), Exists: exists, Valid: valid},
		Modules: mods,
		Update:  a.updateFragment(),
	}
	if a.JSON {
		a.emit("status", data)
		return 0
	}
	a.Log.Info("EasyWork " + a.Version)
	for _, m := range mods {
		switch m.State {
		case "true":
			a.Log.Success(m.Name)
		case "failed":
			a.Log.Error(m.Name + "  （安装失败）")
		default:
			a.Log.Info(m.Name + "  （未安装）")
		}
	}
	return 0
}

// ─── list ─────────────────────────────────────────────────────

func (a *App) cmdList() int {
	mods := make([]listModule, 0, len(modules.All()))
	for _, m := range modules.All() {
		entry := listModule{Name: m.Name(), Description: m.Description(), Priority: m.Priority(), Optional: modules.IsOptional(m)}
		for _, c := range modules.Components(m) {
			entry.Components = append(entry.Components, listComponent{Name: c.Name, Description: c.Description})
		}
		mods = append(mods, entry)
	}
	if a.JSON {
		a.emit("list", listData{Modules: mods, Update: a.updateFragment()})
		return 0
	}
	for _, m := range mods {
		desc := m.Description
		if m.Optional {
			desc += "（可选，默认不装）"
		}
		fmt.Fprintf(a.Log.Out, "  %-12s %s\n", m.Name, desc)
		for _, c := range m.Components {
			fmt.Fprintf(a.Log.Out, "      %-8s %s\n", c.Name, c.Description)
		}
	}
	return 0
}

// ─── version ──────────────────────────────────────────────────

func (a *App) cmdVersion() int {
	installed := []string{}
	installDate := ""
	if a.Manifest.Exists() {
		installDate = a.Manifest.InstallDate()
		installed = a.Manifest.ListInstalled()
		for i, n := range installed {
			installed[i] = modules.Canonical(n)
		}
	}
	data := versionData{
		Version:     a.Version,
		Channel:     a.Channel,
		InstallDate: installDate,
		Installed:   installed,
		Update:      a.updateFragment(),
	}
	if a.JSON {
		a.emit("version", data)
		return 0
	}
	label := a.Version
	if a.Channel != "" {
		label += " (" + a.Channel + ")"
	}
	fmt.Fprintf(a.Log.Out, "EasyWork %s\n", label)
	return 0
}

// ─── doctor ───────────────────────────────────────────────────

func (a *App) cmdDoctor() int {
	checks := a.doctorChecks()
	if a.JSON {
		a.emit("doctor", doctorData{Checks: checks, Update: a.updateFragment()})
		return 0
	}
	for _, c := range checks {
		mark := "✓"
		if !c.OK {
			mark = "✗"
		}
		fmt.Fprintf(a.Log.Out, "  %s %-8s %s\n", mark, c.Name, c.Detail)
	}
	return 0
}

// doctorChecks 按平台生成诊断项（Windows 无 awk/sed/zsh）。
func (a *App) doctorChecks() []checkItem {
	checks := []checkItem{}
	if platform.DetectOS() == platform.Windows {
		for _, name := range []string{"git", "curl"} {
			checks = append(checks, toolCheck(name, "missing"))
		}
		for _, name := range []string{"node", "npm"} {
			checks = append(checks, toolCheck(name, "optional (AI 工具安装需要)"))
		}
	} else {
		for _, name := range []string{"curl", "git", "awk", "sed"} {
			checks = append(checks, toolCheck(name, "missing"))
		}
		checks = append(checks, toolCheck("zsh", "optional (Oh My Zsh 将跳过)"))
	}
	// 控制台编码诊断：Windows 上 ew 启动时会把代码页切到 65001，
	// 中文仍乱码时可据此确认是终端/字体问题还是编码问题。
	cp := platform.ConsoleCodePage()
	detail := "utf-8 (n/a)"
	if cp != 0 {
		detail = "cp=" + strconv.Itoa(cp)
		if cp != 65001 {
			detail += " (非 UTF-8，中文可能乱码)"
		}
	}
	checks = append(checks, checkItem{Name: "console", OK: cp == 0 || cp == 65001, Detail: detail})

	if checkNetwork() {
		checks = append(checks, checkItem{Name: "network", OK: true, Detail: "github.com reachable"})
	} else {
		checks = append(checks, checkItem{Name: "network", OK: false, Detail: "github.com unreachable"})
	}
	return checks
}

func toolCheck(name, missingDetail string) checkItem {
	if p := platform.CmdPath(name); p != "" {
		return checkItem{Name: name, OK: true, Detail: platform.ToSlash(p)}
	}
	return checkItem{Name: name, OK: false, Detail: missingDetail}
}

func checkNetwork() bool {
	conn, err := net.DialTimeout("tcp", "github.com:443", 5*time.Second)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

// ─── update ───────────────────────────────────────────────────

var apiURL = defaultAPIURL()

func defaultAPIURL() string {
	if u := os.Getenv("EASYWORK_API_URL"); u != "" {
		return u
	}
	return version.APIDefault
}

func (a *App) resolveLatestVersion() string {
	cache := a.Env.UpdateCachePath()
	now := time.Now().Unix()
	if data, err := os.ReadFile(cache); err == nil {
		lines := strings.Split(string(data), "\n")
		if len(lines) >= 2 {
			last, convErr := strconv.ParseInt(strings.TrimSpace(lines[0]), 10, 64)
			if convErr != nil {
				last = 0
			}
			latest := strings.TrimSpace(lines[1])
			if now-last < 86400 {
				return latest
			}
		}
	}
	latest := fetchLatestVersion()
	_ = a.Env.EnsureHome()
	_ = os.WriteFile(cache, []byte(fmt.Sprintf("%d\n%s\n", now, latest)), 0o644)
	return latest
}

func fetchLatestVersion() string {
	client := &http.Client{Timeout: 6 * time.Second}
	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		return ""
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return ""
	}
	var parsed struct {
		TagName string `json:"tag_name"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil || parsed.TagName == "" {
		return ""
	}
	return parsed.TagName
}

func (a *App) updateFragment() updateInfo {
	if a.Offline {
		return updateInfo{}
	}
	latest := a.resolveLatestVersion()
	if latest == "" {
		return updateInfo{}
	}
	v := latest
	return updateInfo{Latest: &v, Available: semverNewer(latest, a.Version)}
}

func parseSemver(v string) [3]int {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	if i := strings.IndexAny(v, "-+"); i >= 0 {
		v = v[:i]
	}
	parts := strings.Split(v, ".")
	var out [3]int
	for i := 0; i < 3 && i < len(parts); i++ {
		n, _ := strconv.Atoi(parts[i])
		out[i] = n
	}
	return out
}

func semverNewer(a, b string) bool {
	pa, pb := parseSemver(a), parseSemver(b)
	for i := 0; i < 3; i++ {
		if pa[i] != pb[i] {
			return pa[i] > pb[i]
		}
	}
	return false
}
