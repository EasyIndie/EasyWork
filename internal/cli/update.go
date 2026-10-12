package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/platform"
	"github.com/EasyIndie/EasyWork/internal/release"
)

// releaseBaseURL 返回发布资产基址（可经 EASYWORK_RELEASE_URL 覆盖，用于镜像）。
func releaseBaseURL() string {
	if u := os.Getenv("EASYWORK_RELEASE_URL"); u != "" {
		return strings.TrimRight(u, "/")
	}
	return "https://github.com/EasyIndie/EasyWork/releases/download"
}

// cmdUpdate 检查并自升级：下载对应平台归档 → 校验 → 替换当前二进制 → 重跑 install。
func (a *App) cmdUpdate() int {
	if a.Offline {
		return a.fail(3, "离线模式：跳过更新检查")
	}

	a.Log.Info("检查更新...")
	tag := fetchLatestVersion()
	if tag == "" {
		return a.fail(3, "无法检查更新，请检查网络连接")
	}
	latest := strings.TrimPrefix(tag, "v")
	if !semverNewer(latest, a.Version) {
		a.Log.Success("已是最新版本 " + a.Version)
		return 0
	}
	a.Log.Info("当前版本: " + a.Version)
	a.Log.Info("最新版本: " + latest)

	if !a.Yes {
		if !isTerminal(os.Stdin) {
			a.Log.Info("非交互模式，跳过升级（使用 --yes 以自动升级）")
			return 0
		}
		if !promptYesNo("  升级到 " + latest + "？[Y/n] ") {
			a.Log.Info("已取消升级")
			return 0
		}
	}

	if a.DryRun {
		a.Log.Info("[DRY-RUN] 将下载并安装 " + latest)
		return 0
	}

	base := releaseBaseURL()
	asset := release.AssetName(latest, runtime.GOOS, runtime.GOARCH)
	url := base + "/" + tag + "/" + asset

	tmpDir, err := os.MkdirTemp("", "ew-update-")
	if err != nil {
		return a.fail(1, "无法创建临时目录: "+err.Error())
	}
	defer func() { _ = os.RemoveAll(tmpDir) }()
	archive := filepath.Join(tmpDir, asset)

	a.Log.Info("下载 " + url + " ...")
	if err := platform.Download(url, archive); err != nil {
		return a.fail(3, "下载失败，已保留当前版本")
	}

	if ok, verr := a.verifyChecksum(base, tag, asset, archive); !ok {
		msg := "文件完整性校验失败，放弃更新"
		if verr != nil {
			msg += ": " + verr.Error()
		}
		return a.fail(3, msg)
	} else {
		a.Log.Success("SHA256 校验通过")
	}

	bin, err := release.ExtractBinary(archive, tmpDir)
	if err != nil {
		return a.fail(1, "解包失败: "+err.Error())
	}

	if err := replaceExecutable(bin); err != nil {
		return a.fail(4, "无法写入新版本: "+err.Error())
	}
	a.Log.Success("已更新到 " + latest)

	if os.Getenv("EASYWORK_UPDATE_SKIP_REINSTALL") == "true" {
		a.Log.Info("已跳过重新应用配置（EASYWORK_UPDATE_SKIP_REINSTALL=true）")
		return 0
	}

	exe, err := os.Executable()
	if err != nil {
		a.Log.Warn("请手动运行: ew install --yes")
		return 0
	}
	a.Log.Info("应用最新配置...")
	return runInstallWith(exe)
}

// verifyChecksum 下载 checksums.txt 并校验归档；无校验文件时跳过（返回 true）。
func (a *App) verifyChecksum(base, tag, asset, archive string) (bool, error) {
	tmp := archive + ".checksums"
	if err := platform.Download(base+"/"+tag+"/checksums.txt", tmp); err != nil {
		a.Log.Debug("无 checksums.txt，跳过完整性校验")
		return true, nil
	}
	data, err := os.ReadFile(tmp)
	if err != nil {
		return true, nil
	}
	want := release.ParseChecksums(string(data), asset)
	if want == "" {
		return true, nil
	}
	got, err := release.SHA256File(archive)
	if err != nil {
		return false, err
	}
	if got != want {
		return false, fmt.Errorf("校验和不匹配：期望 %s，实际 %s", want, got)
	}
	return true, nil
}

// replaceExecutable 用 newBin 替换当前运行的可执行文件（跨平台）。
// Unix：同目录 staged 后 rename 覆盖。
// Windows：运行中的 exe 不能删除，但可 rename；先把旧文件改名再换入新文件。
func replaceExecutable(newBin string) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if resolved, e := filepath.EvalSymlinks(exe); e == nil {
		exe = resolved
	}
	dir := filepath.Dir(exe)
	staged := filepath.Join(dir, filepath.Base(exe)+".new")
	if err := copyFile(newBin, staged, 0o755); err != nil {
		return err
	}

	if platform.DetectOS() == platform.Windows {
		old := exe + ".old"
		_ = os.Remove(old)
		if err := os.Rename(exe, old); err != nil {
			_ = os.Remove(staged)
			return err
		}
		if err := os.Rename(staged, exe); err != nil {
			_ = os.Rename(old, exe) // 回滚
			return err
		}
		_ = os.Remove(old)
		alias := filepath.Join(dir, "easywork.exe")
		if _, e := os.Stat(alias); e == nil {
			_ = copyFile(exe, alias, 0o755)
		}
		return nil
	}

	if err := os.Chmod(staged, 0o755); err != nil {
		return err
	}
	return os.Rename(staged, exe)
}

func copyFile(src, dst string, perm os.FileMode) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if err := os.WriteFile(dst, data, perm); err != nil {
		return err
	}
	return os.Chmod(dst, perm)
}

// runInstallWith 运行新二进制以应用配置，返回其退出码。
func runInstallWith(exe string) int {
	cmd := exec.Command(exe, "install", "--yes")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		return 0
	}
	return 0
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	return err == nil && (fi.Mode()&os.ModeCharDevice) != 0
}

func promptYesNo(prompt string) bool {
	fmt.Fprint(os.Stderr, prompt)
	var s string
	_, _ = fmt.Fscanln(os.Stdin, &s)
	s = strings.ToLower(strings.TrimSpace(s))
	return s == "" || !strings.HasPrefix(s, "n")
}
