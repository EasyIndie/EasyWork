// Command ew 是 EasyWork 的跨平台入口。
package main

import (
	"os"

	"github.com/EasyIndie/EasyWork/internal/cli"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

func main() {
	// Windows 控制台默认代码页 GBK(936)，而 Go 按 UTF-8 写 stdout：
	// 启动时切到 65001 并开启 ANSI 处理，退出时还原。其他平台为 no-op。
	restoreConsole := platform.EnableUTF8Console()
	code := cli.Run(os.Args[1:])
	restoreConsole()
	os.Exit(code)
}
