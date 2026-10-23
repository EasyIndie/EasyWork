//go:build !windows

package platform

import "io"

// ConsoleOutput 在非 Windows 平台原样返回：终端始终按 UTF-8 解析。
func ConsoleOutput(w io.Writer) io.Writer { return w }
