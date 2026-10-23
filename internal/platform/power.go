package platform

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// OnAC 报告当前是否接通外部电源。
// 无法判断时返回 true（台式机/容器场景按常电处理，避免误报"电池供电"）。
func OnAC() bool {
	switch DetectOS() {
	case MacOS:
		out, err := exec.Command("pmset", "-g", "batt").Output()
		if err != nil {
			return true
		}
		return strings.Contains(string(out), "AC Power")
	case Linux:
		for _, name := range []string{"AC", "AC0", "AC1", "ADP1", "ADP0"} {
			data, err := os.ReadFile("/sys/class/power_supply/" + name + "/online")
			if err != nil {
				continue
			}
			return strings.TrimSpace(string(data)) == "1"
		}
		return true
	case Windows:
		script := "(Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus | Select-Object -First 1).PowerOnline"
		out, err := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", script).Output()
		if err != nil {
			return true
		}
		return strings.Contains(strings.ToLower(string(out)), "true")
	}
	return true
}

// SleepPolicy 是 pmset 的空闲睡眠策略（macOS）。
type SleepPolicy struct {
	Sleep        int // 分钟；0 = 永不
	DisplaySleep int
	DiskSleep    int
	OnAC         bool
}

// SleepPolicies 一次性读取 pmset 的电源策略分支。
// 两侧都要看：只报当前分支会漏掉另一侧的矛盾（拔电后才发现设置没生效）。
// 返回的切片只含**实际存在**的分支（AC 在前）：台式机与虚拟机没有电池分支，
// 若强行要求两侧齐全，这些机器会永远拿不到 sleep-policy 诊断。
func SleepPolicies() []SleepPolicy {
	if DetectOS() != MacOS {
		return nil
	}
	out, err := exec.Command("pmset", "-g", "custom").Output()
	if err != nil {
		return nil
	}
	return ParseSleepPolicies(string(out))
}

// ParseSleepPolicies 从 `pmset -g custom` 输出中解析出实际出现的分支（AC 在前）。
func ParseSleepPolicies(text string) []SleepPolicy {
	var pols []SleepPolicy
	for _, onAC := range []bool{true, false} {
		if pol, ok := ParseSleepPolicy(text, onAC); ok {
			pols = append(pols, pol)
		}
	}
	return pols
}

// ParseSleepPolicy 从 `pmset -g custom` 输出中解析指定电源分支。
func ParseSleepPolicy(text string, onAC bool) (SleepPolicy, bool) {
	want := "Battery Power:"
	if onAC {
		want = "AC Power:"
	}
	pol := SleepPolicy{OnAC: onAC}
	section := ""
	found := false
	for _, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" {
			continue
		}
		if strings.HasSuffix(line, ":") {
			section = line
			continue
		}
		if section != want {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		n, err := strconv.Atoi(fields[1])
		if err != nil {
			continue
		}
		switch fields[0] {
		case "sleep":
			pol.Sleep, found = n, true
		case "displaysleep":
			pol.DisplaySleep = n
		case "disksleep":
			pol.DiskSleep = n
		}
	}
	return pol, found
}

// Problems 返回策略中的自相矛盾项（pmset 自身也会为此告警）；空表示自洽。
func (p SleepPolicy) Problems() []string {
	var out []string
	if p.Sleep > 0 && p.DisplaySleep >= p.Sleep {
		out = append(out, "displaysleep 应小于 sleep（否则熄屏设置不生效）")
	}
	if p.Sleep > 0 && p.DiskSleep == 0 {
		out = append(out, "disksleep 应为非零（sleep 非零时）")
	}
	return out
}
