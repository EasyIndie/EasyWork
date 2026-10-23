// Package engine 实现与语言无关的五个契约（config/manifest/managed/json）。
package engine

import (
	"os"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

// Config 是 config.toml 的访问器（契约二）。
type Config struct {
	path string
}

// NewConfig 绑定到 env 的 config.toml。
func NewConfig(env platform.Env) Config { return Config{path: env.ConfigPath()} }

// Path 返回配置文件路径。
func (c Config) Path() string { return c.path }

// splitKey 把 a.b.c 拆为 (a.b, c)；无点则为 ("", key)。
func splitKey(key string) (section, name string) {
	if i := strings.LastIndex(key, "."); i >= 0 {
		return key[:i], key[i+1:]
	}
	return "", key
}

// parseValue 解析 'key = value' 的右值，支持 cfg_set 产生的转义。
func parseValue(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "\"") {
		raw = raw[1:]
		var out strings.Builder
		esc := false
		for _, r := range raw {
			if esc {
				switch r {
				case '"':
					out.WriteByte('"')
				case '\\':
					out.WriteByte('\\')
				case 'n':
					out.WriteByte('\n')
				case 't':
					out.WriteByte('\t')
				default:
					out.WriteByte('\\')
					out.WriteRune(r)
				}
				esc = false
				continue
			}
			if r == '\\' {
				esc = true
				continue
			}
			if r == '"' {
				break
			}
			out.WriteRune(r)
		}
		return out.String()
	}
	if i := strings.Index(raw, "#"); i >= 0 {
		raw = raw[:i]
	}
	return strings.TrimSpace(raw)
}

// escapeValue 转义值用于双引号字符串（与 cfg_set 一致）。
func escapeValue(v string) string {
	v = strings.ReplaceAll(v, "\\", "\\\\")
	v = strings.ReplaceAll(v, "\"", "\\\"")
	return v
}

// Get 读取标量；未命中返回 def。
func (c Config) Get(key, def string) string {
	data, err := os.ReadFile(c.path)
	if err != nil {
		return def
	}
	wantSection, wantKey := splitKey(key)
	cur := ""
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			cur = strings.TrimSpace(line[1 : len(line)-1])
			continue
		}
		if cur != wantSection {
			continue
		}
		eq := strings.Index(line, "=")
		if eq < 0 {
			continue
		}
		if strings.TrimSpace(line[:eq]) != wantKey {
			continue
		}
		return parseValue(line[eq+1:])
	}
	return def
}

// GetBool 读取布尔值并归一化。
func (c Config) GetBool(key string, def bool) bool {
	d := "false"
	if def {
		d = "true"
	}
	switch strings.ToLower(c.Get(key, d)) {
	case "true", "1", "yes", "on":
		return true
	case "false", "0", "no", "off":
		return false
	default:
		return def
	}
}

// Has 报告某个键是否在 config.toml 中被显式写出（用于区分「缺省」与「显式关闭」）。
func (c Config) Has(key string) bool {
	data, err := os.ReadFile(c.path)
	if err != nil {
		return false
	}
	wantSection, wantKey := splitKey(key)
	cur := ""
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			cur = strings.TrimSpace(line[1 : len(line)-1])
			continue
		}
		if cur != wantSection {
			continue
		}
		eq := strings.Index(line, "=")
		if eq < 0 {
			continue
		}
		if strings.TrimSpace(line[:eq]) == wantKey {
			return true
		}
	}
	return false
}

// Valid 校验 schema_version（文件不存在视为合法）。
func (c Config) Valid() bool {
	if _, err := os.Stat(c.path); err != nil {
		return true
	}
	return c.Get("schema_version", "1") == "1"
}

func keyLine(name, value string) string {
	return name + " = \"" + escapeValue(value) + "\""
}

// Set 幂等 upsert 一个标量，保留其余内容与顺序。
// 无点号键为顶层键；有点号为 section.key。
func (c Config) Set(key, value string) error {
	section, keyname := splitKey(key)
	var out []string
	sectionFound := false
	keyWritten := false
	cur := ""
	// 顶层键：无 section 头时 cur=="" 即为目标上下文
	inTarget := section == ""
	if inTarget {
		sectionFound = true
	}

	if data, err := os.ReadFile(c.path); err == nil {
		body := strings.TrimSuffix(string(data), "\n")
		if body != "" {
			for _, raw := range strings.Split(body, "\n") {
				line := strings.TrimSuffix(raw, "\r")
				trimmed := strings.TrimSpace(line)
				if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
					if inTarget && !keyWritten {
						out = append(out, keyLine(keyname, value))
						keyWritten = true
					}
					cur = strings.TrimSpace(trimmed[1 : len(trimmed)-1])
					inTarget = cur == section
					if inTarget {
						sectionFound = true
					}
					out = append(out, line)
					continue
				}
				if inTarget {
					if eq := strings.Index(trimmed, "="); eq >= 0 && strings.TrimSpace(trimmed[:eq]) == keyname {
						out = append(out, keyLine(keyname, value))
						keyWritten = true
						continue
					}
				}
				out = append(out, line)
			}
		}
	} else {
		// 文件不存在：section 键需先补 schema_version；顶层键由后续追加写入。
		if section != "" {
			out = append(out, "schema_version = 1")
		}
	}

	if inTarget && !keyWritten {
		out = append(out, keyLine(keyname, value))
		keyWritten = true
	}
	if !sectionFound {
		if section == "" {
			out = append(out, keyLine(keyname, value))
		} else {
			out = append(out, "", "["+section+"]", keyLine(keyname, value))
		}
	}

	return platform.AtomicWrite(c.path, []byte(strings.Join(out, "\n")+"\n"), 0o644)
}

// defaultTemplate 是新环境的默认 config.toml（格式为契约，跨版本不变）。
const defaultTemplate = `# EasyWork 配置文件（v2）
# 编辑: easywork config edit
# 或:   easywork config set <键> <值>
schema_version = 1

[shell]
enable_aliases      = true
enable_fancy_prompt = false
enable_ohmyzsh      = false
enable_net_tools    = false

[git]
identity = "personal"
scope    = "global"

[ai]
install = true
# 细粒度选择（空格分隔子工具）: claude codex pi
# 留空/注释掉 = 全部；例: tools = "claude codex"
# tools = "claude codex pi"

[keepawake]
enabled = false
mode    = "ac"
display = false
persist = false
`

// Ensure 在 config.toml 缺失时创建（优先迁移旧 ini）。
func (c Config) Ensure(env platform.Env) (created bool, err error) {
	if _, statErr := os.Stat(c.path); statErr == nil {
		return false, nil
	}
	if _, statErr := os.Stat(env.LegacyConfigPath()); statErr == nil {
		return false, Migrate(env)
	}
	if err := env.EnsureHome(); err != nil {
		return false, err
	}
	if err := platform.AtomicWrite(c.path, []byte(defaultTemplate), 0o644); err != nil {
		return false, err
	}
	return true, nil
}

// Migrate 把旧 ini 迁移到 config.toml（仅在 config.toml 不存在时）。
func Migrate(env platform.Env) error {
	c := NewConfig(env)
	if _, err := os.Stat(c.path); err == nil {
		return nil
	}
	data, err := os.ReadFile(env.LegacyConfigPath())
	if err != nil {
		return nil
	}
	vars := parseINI(string(data))
	content := "schema_version = 1\n\n" +
		"[git.identities.personal]\n" +
		"name  = \"" + escapeValue(vars["GIT_PERSONAL_NAME"]) + "\"\n" +
		"email = \"" + escapeValue(vars["GIT_PERSONAL_EMAIL"]) + "\"\n\n" +
		"[git.identities.work]\n" +
		"name  = \"" + escapeValue(vars["GIT_WORK_NAME"]) + "\"\n" +
		"email = \"" + escapeValue(vars["GIT_WORK_EMAIL"]) + "\"\n"
	if err := env.EnsureHome(); err != nil {
		return err
	}
	return platform.AtomicWrite(c.path, []byte(content), 0o644)
}

func parseINI(data string) map[string]string {
	out := map[string]string{}
	for _, raw := range strings.Split(data, "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "[") {
			continue
		}
		if eq := strings.Index(line, "="); eq >= 0 {
			k := strings.TrimSpace(line[:eq])
			v := strings.TrimSpace(line[eq+1:])
			v = strings.Trim(v, `"'`)
			out[k] = v
		}
	}
	return out
}
