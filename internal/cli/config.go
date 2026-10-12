package cli

import (
	"fmt"
	"os"
	"os/exec"
)

// cmdConfig 实现 config get/set/show/edit。
func (a *App) cmdConfig(args []string) int {
	sub := "show"
	if len(args) > 0 {
		sub = args[0]
	}
	switch sub {
	case "get":
		if len(args) < 2 {
			return a.fail(1, "用法: ew config get <键>")
		}
		fmt.Fprint(a.Log.Out, a.Config.Get(args[1], ""))
		return 0
	case "set":
		if len(args) < 3 {
			return a.fail(1, "用法: ew config set <键> <值>")
		}
		if err := a.Config.Set(args[1], args[2]); err != nil {
			return a.fail(1, "写入配置失败: "+err.Error())
		}
		return 0
	case "show":
		data, err := os.ReadFile(a.Config.Path())
		if err != nil {
			a.Log.Info("配置文件未创建: " + a.Config.Path())
			return 0
		}
		_, _ = a.Log.Out.Write(data)
		return 0
	case "edit":
		if _, err := a.Config.Ensure(a.Env); err != nil {
			return a.fail(1, "创建配置失败: "+err.Error())
		}
		editor := os.Getenv("EDITOR")
		if editor == "" {
			editor = "vi"
		}
		cmd := exec.Command(editor, a.Config.Path())
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return a.fail(1, "编辑器退出异常: "+err.Error())
		}
		return 0
	default:
		a.Log.Info("用法: ew config [show|edit|get K|set K V]")
		return a.fail(1, "未知 config 子命令: "+sub)
	}
}
