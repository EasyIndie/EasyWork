package platform

import (
	"os"
	"os/exec"
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
