// Command ew 是 EasyWork 的跨平台入口。
package main

import (
	"os"

	"github.com/EasyIndie/EasyWork/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:]))
}
