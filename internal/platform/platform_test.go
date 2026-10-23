package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestNewEnvEasyworkHomeOverride(t *testing.T) {
	t.Setenv("HOME", "/tmp/ew-test-home")
	t.Setenv("EASYWORK_HOME", "/tmp/ew-test-home/custom")
	env := NewEnv()
	if env.EasyworkHome != "/tmp/ew-test-home/custom" {
		t.Fatalf("override not honored: %s", env.EasyworkHome)
	}
	if env.ConfigPath() != filepath.Join("/tmp/ew-test-home/custom", "config.toml") {
		t.Fatalf("config path wrong: %s", env.ConfigPath())
	}
}

func TestNewEnvDefaultHome(t *testing.T) {
	t.Setenv("HOME", "/tmp/ew-home")
	t.Setenv("EASYWORK_HOME", "")
	env := NewEnv()
	want := filepath.Join("/tmp/ew-home", ".easywork")
	if env.EasyworkHome != want {
		t.Fatalf("default home wrong: got %s want %s", env.EasyworkHome, want)
	}
}

func TestDetectOS(t *testing.T) {
	os := DetectOS()
	switch runtime.GOOS {
	case "darwin":
		if os != MacOS {
			t.Fatalf("want macos got %s", os)
		}
	case "linux":
		if os != Linux {
			t.Fatalf("want linux got %s", os)
		}
	case "windows":
		if os != Windows {
			t.Fatalf("want windows got %s", os)
		}
	}
}

func TestAtomicWrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sub", "file.txt")
	if err := AtomicWrite(path, []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "hello" {
		t.Fatalf("read back failed: %q err=%v", data, err)
	}
	// 覆盖写
	if err := AtomicWrite(path, []byte("world"), 0o644); err != nil {
		t.Fatal(err)
	}
	data, _ = os.ReadFile(path)
	if string(data) != "world" {
		t.Fatalf("overwrite failed: %q", data)
	}
}

// EnableUTF8Console 在各平台都必须可用且幂等（Windows 上是真调用，其余为 no-op）。
func TestEnableUTF8ConsoleIdempotent(t *testing.T) {
	restore1 := EnableUTF8Console()
	restore1()
	restore2 := EnableUTF8Console()
	restore2()
}

func TestParseSleepPolicyBatteryBranch(t *testing.T) {
	out := `Battery Power:
 lidwake              1
 displaysleep         30
 sleep                10
 disksleep            0
AC Power:
 displaysleep         10
 sleep                0
 disksleep            10
`
	pol, ok := ParseSleepPolicy(out, false)
	if !ok {
		t.Fatal("应解析出电池分支")
	}
	if pol.Sleep != 10 || pol.DisplaySleep != 30 || pol.DiskSleep != 0 || pol.OnAC {
		t.Fatalf("电池分支解析错误: %+v", pol)
	}
	problems := pol.Problems()
	if len(problems) != 2 {
		t.Fatalf("应报出 2 条矛盾（displaysleep>=sleep、disksleep=0），得到 %v", problems)
	}

	ac, ok := ParseSleepPolicy(out, true)
	if !ok || ac.Sleep != 0 || !ac.OnAC {
		t.Fatalf("AC 分支解析错误: %+v ok=%v", ac, ok)
	}
	if len(ac.Problems()) != 0 {
		t.Fatalf("sleep=0 时应视为自洽，得到 %v", ac.Problems())
	}
}

func TestParseSleepPolicyRejectsGarbage(t *testing.T) {
	if _, ok := ParseSleepPolicy("no sections here\n", false); ok {
		t.Fatal("无对应分支时应返回 ok=false")
	}
}

func TestParseSleepPolicyConsistent(t *testing.T) {
	out := "Battery Power:\n displaysleep         10\n sleep                30\n disksleep            10\n"
	pol, ok := ParseSleepPolicy(out, false)
	if !ok || len(pol.Problems()) != 0 {
		t.Fatalf("10/30/10 应判定自洽，得到 %+v problems=%v", pol, pol.Problems())
	}
}

func TestParseSleepPolicyBothBranches(t *testing.T) {
	out := `Battery Power:
 displaysleep         10
 sleep                30
 disksleep            10
AC Power:
 displaysleep         30
 sleep                60
 disksleep            10
`
	ac, bat, ok := func() (SleepPolicy, SleepPolicy, bool) {
		a, okA := ParseSleepPolicy(out, true)
		b, okB := ParseSleepPolicy(out, false)
		return a, b, okA && okB
	}()
	if !ok {
		t.Fatal("两侧都应解析成功")
	}
	if ac.Sleep != 60 || ac.DisplaySleep != 30 || ac.DiskSleep != 10 {
		t.Fatalf("AC 解析错误: %+v", ac)
	}
	if bat.Sleep != 30 || bat.DisplaySleep != 10 || bat.DiskSleep != 10 {
		t.Fatalf("Battery 解析错误: %+v", bat)
	}
	if len(ac.Problems()) != 0 || len(bat.Problems()) != 0 {
		t.Fatalf("两侧自洽却报问题: ac=%v bat=%v", ac.Problems(), bat.Problems())
	}
}

// 台式机 / CI 虚拟机只有 AC 分支：必须照常返回 AC，不得因缺电池而整体放弃。
func TestParseSleepPoliciesDesktopACOnly(t *testing.T) {
	out := `AC Power:
 displaysleep         30
 sleep                0
 disksleep            0
`
	pols := ParseSleepPolicies(out)
	if len(pols) != 1 {
		t.Fatalf("台式机应只解析出 AC 分支，得到 %d 个: %+v", len(pols), pols)
	}
	if !pols[0].OnAC || pols[0].DisplaySleep != 30 || pols[0].Sleep != 0 {
		t.Fatalf("AC 分支解析错误: %+v", pols[0])
	}
	// sleep=0（永不）不判为矛盾。
	if len(pols[0].Problems()) != 0 {
		t.Fatalf("sleep=0 应视为自洽，得到 %v", pols[0].Problems())
	}
}

// AC 在前、电池在后的稳定顺序（doctor 的 detail 依赖它）。
func TestParseSleepPoliciesOrderAndCount(t *testing.T) {
	out := `Battery Power:
 sleep                30
 displaysleep         10
 disksleep            10
AC Power:
 sleep                60
 displaysleep         30
 disksleep            10
`
	pols := ParseSleepPolicies(out)
	if len(pols) != 2 {
		t.Fatalf("两侧齐全时应返回 2 个分支，得到 %d 个: %+v", len(pols), pols)
	}
	if !pols[0].OnAC || pols[1].OnAC {
		t.Fatalf("分支顺序应为 AC、Battery，得到 %+v", pols)
	}
}

// 无任何可解析分支（pmset 输出异常）时返回空，doctor 不输出该项。
func TestParseSleepPoliciesEmpty(t *testing.T) {
	if pols := ParseSleepPolicies("garbage\n"); len(pols) != 0 {
		t.Fatalf("无分支时应返回空，得到 %+v", pols)
	}
}
