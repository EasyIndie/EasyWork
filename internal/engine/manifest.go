package engine

import (
	"os"
	"strings"
	"time"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// Manifest 是安装状态的访问器（契约三）。
type Manifest struct {
	path string
}

// NewManifest 绑定到 env 的 manifest。
func NewManifest(env platform.Env) Manifest { return Manifest{path: env.ManifestPath()} }

// Path 返回 manifest 路径。
func (m Manifest) Path() string { return m.path }

// Exists 报告 manifest 是否存在。
func (m Manifest) Exists() bool {
	_, err := os.Stat(m.path)
	return err == nil
}

func (m Manifest) lines() ([]string, error) {
	data, err := os.ReadFile(m.path)
	if err != nil {
		return nil, err
	}
	body := strings.TrimSuffix(string(data), "\n")
	if body == "" {
		return nil, nil
	}
	raw := strings.Split(body, "\n")
	out := make([]string, 0, len(raw))
	for _, l := range raw {
		out = append(out, strings.TrimSuffix(l, "\r"))
	}
	return out, nil
}

// Read 读取顶层键（首个 `key=` 起始的行）；未命中返回 def。
func (m Manifest) Read(key, def string) string {
	lines, err := m.lines()
	if err != nil {
		return def
	}
	for _, line := range lines {
		if strings.HasPrefix(line, key+"=") {
			return strings.TrimPrefix(line, key+"=")
		}
	}
	return def
}

// ReadSectionKey 在 [section] 内读取键；遇下一节停止。
func (m Manifest) ReadSectionKey(section, key, def string) string {
	lines, err := m.lines()
	if err != nil {
		return def
	}
	in := false
	header := "[" + section + "]"
	for _, line := range lines {
		if line == header {
			in = true
			continue
		}
		if in && strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			break
		}
		if in && strings.HasPrefix(line, key+"=") {
			return strings.TrimPrefix(line, key+"=")
		}
	}
	return def
}

// SectionExists 报告节是否存在。
func (m Manifest) SectionExists(section string) bool {
	lines, err := m.lines()
	if err != nil {
		return false
	}
	header := "[" + section + "]"
	for _, line := range lines {
		if line == header {
			return true
		}
	}
	return false
}

// ModuleState 返回模块安装状态（true|false|failed|absent）。
func (m Manifest) ModuleState(name string) string {
	if !m.Exists() {
		return "absent"
	}
	v := m.ReadSectionKey(name, "installed", "")
	if v == "" {
		return "absent"
	}
	return v
}

// GetVersion 返回 manifest 记录的版本。
func (m Manifest) GetVersion() string { return m.Read("easywork_version", "0.0.0") }

// InstallDate 返回安装时间字符串。
func (m Manifest) InstallDate() string { return m.Read("install_date", "") }

// ListInstalled 返回所有 installed=true 的节名（按出现顺序）。
func (m Manifest) ListInstalled() []string {
	lines, err := m.lines()
	if err != nil {
		return nil
	}
	var out []string
	section := ""
	for _, line := range lines {
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = line[1 : len(line)-1]
			continue
		}
		if section != "" && line == "installed=true" {
			out = append(out, section)
		}
	}
	return out
}

// Init 新建 manifest。
func (m Manifest) Init(env platform.Env, version string) error {
	if err := env.EnsureHome(); err != nil {
		return err
	}
	content := "# EasyWork Manifest — auto-generated, do not edit\n" +
		"schema_version=1\n" +
		"easywork_version=" + version + "\n" +
		"install_date=" + nowStamp() + "\n"
	return platform.AtomicWrite(m.path, []byte(content), 0o644)
}

// SetSection 整节替换，保留其他内容。
func (m Manifest) SetSection(name string, pairs ...string) error {
	var out []string
	if lines, err := m.lines(); err == nil {
		skip := false
		for _, line := range lines {
			header := "[" + name + "]"
			if line == header {
				skip = true
				continue
			}
			if skip {
				if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
					skip = false
					out = append(out, line)
				}
				continue
			}
			out = append(out, line)
		}
	} else {
		out = append(out, "# EasyWork Manifest — auto-generated, do not edit")
	}
	out = append(out, "["+name+"]")
	out = append(out, pairs...)
	return platform.AtomicWrite(m.path, []byte(strings.Join(out, "\n")+"\n"), 0o644)
}

// RemoveSection 删除指定节，保留其余并去除尾部空行。
func (m Manifest) RemoveSection(name string) error {
	lines, err := m.lines()
	if err != nil {
		return nil
	}
	var out []string
	skip := false
	for _, line := range lines {
		header := "[" + name + "]"
		if line == header {
			skip = true
			continue
		}
		if skip {
			if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
				skip = false
				out = append(out, line)
			}
			continue
		}
		out = append(out, line)
	}
	// 去除尾部空行
	for len(out) > 0 && strings.TrimSpace(out[len(out)-1]) == "" {
		out = out[:len(out)-1]
	}
	content := ""
	if len(out) > 0 {
		content = strings.Join(out, "\n") + "\n"
	}
	return platform.AtomicWrite(m.path, []byte(content), 0o644)
}

func nowStamp() string { return time.Now().Format("2006-01-02T15:04:05-0700") }

// SetTop 更新顶层键（保留其余内容）。
func (m Manifest) SetTop(key, value string) error {
	lines, err := m.lines()
	if err != nil {
		return nil
	}
	replaced := false
	for i, line := range lines {
		if strings.HasPrefix(line, key+"=") {
			lines[i] = key + "=" + value
			replaced = true
			break
		}
	}
	if !replaced {
		lines = append(lines, key+"="+value)
	}
	return platform.AtomicWrite(m.path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
