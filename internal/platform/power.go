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

// SleepPolicyNow 读取**当前电源**下的 pmset 策略；非 macOS 或读取失败时 ok=false。
func SleepPolicyNow() (SleepPolicy, bool) {
	if DetectOS() != MacOS {
		return SleepPolicy{}, false
	}
	out, err := exec.Command("pmset", "-g", "custom").Output()
	if err != nil {
		return SleepPolicy{}, false
	}
	return ParseSleepPolicy(string(out), OnAC())
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
