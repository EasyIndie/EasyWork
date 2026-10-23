//go:build windows

package platform

import (
	"syscall"
	"unsafe"
)

var (
	kernel32               = syscall.NewLazyDLL("kernel32.dll")
	procGetConsoleCP       = kernel32.NewProc("GetConsoleCP")
	procSetConsoleCP       = kernel32.NewProc("SetConsoleCP")
	procGetConsoleOutputCP = kernel32.NewProc("GetConsoleOutputCP")
	procSetConsoleOutputCP = kernel32.NewProc("SetConsoleOutputCP")
	procGetStdHandle       = kernel32.NewProc("GetStdHandle")
	procGetConsoleMode     = kernel32.NewProc("GetConsoleMode")
	procSetConsoleMode     = kernel32.NewProc("SetConsoleMode")
)

const (
	// stdOutputHandle 即 GetStdHandle(STD_OUTPUT_HANDLE) = -11。
	stdOutputHandle           = ^uintptr(10)
	enableVirtualTerminalProc = 0x0004
	utf8CodePage              = 65001
)

// originalCP 记录启动时的控制台代码页（-1 表示尚未探测）。
// 输出适配必须用它：EnableUTF8Console 之后实时 CP 已是 65001，
// 用实时值判断会永远跳过「管道转码」分支。
var originalCP = -1

// EnableUTF8Console 把控制台代码页切到 UTF-8(65001)，并开启 ANSI 转义处理，
// 返回恢复函数（退出时还原，避免污染用户的命令行会话）。
//
// 背景：Go 一律以 UTF-8 写 stdout，而 Windows 控制台默认代码页是 936(GBK)，
// 按 GBK 解码形成乱码（实测 outCP=936，中文显示为「寮€鍙戠幆澧?」这类）。
// 无控制台（输出被重定向/管道）时两个 Get*CP 返回 0 或调用失败，整体退化为 no-op。
func EnableUTF8Console() func() {
	_ = kernel32.Load()
	if err := procGetConsoleOutputCP.Find(); err != nil {
		return func() {}
	}
	outCP, _, _ := procGetConsoleOutputCP.Call()
	if originalCP < 0 {
		originalCP = int(outCP)
	}
	if outCP == 0 || outCP == utf8CodePage {
		return func() {}
	}
	inCP, _, _ := procGetConsoleCP.Call()
	_, _, _ = procSetConsoleOutputCP.Call(utf8CodePage)
	if inCP != 0 {
		_, _, _ = procSetConsoleCP.Call(utf8CodePage)
	}
	restoreVT := enableVirtualTerminal()

	return func() {
		_, _, _ = procSetConsoleOutputCP.Call(outCP)
		if inCP != 0 {
			_, _, _ = procSetConsoleCP.Call(inCP)
		}
		restoreVT()
	}
}

// OriginalConsoleCodePage 返回进程启动时的控制台输出代码页；无控制台时为 0。
func OriginalConsoleCodePage() int {
	if originalCP < 0 {
		if err := procGetConsoleOutputCP.Find(); err == nil {
			cp, _, _ := procGetConsoleOutputCP.Call()
			originalCP = int(cp)
		}
	}
	if originalCP < 0 {
		return 0
	}
	return originalCP
}

// ConsoleCodePage 返回当前控制台输出代码页；无控制台时返回 0。
func ConsoleCodePage() int {
	if err := procGetConsoleOutputCP.Find(); err != nil {
		return 0
	}
	cp, _, _ := procGetConsoleOutputCP.Call()
	return int(cp)
}

// enableVirtualTerminal 打开 ENABLE_VIRTUAL_TERMINAL_PROCESSING，
// 让 ANSI 颜色在 conhost/Windows Terminal 正常生效（不支持时静默跳过）。
func enableVirtualTerminal() func() {
	h, _, _ := procGetStdHandle.Call(stdOutputHandle)
	var mode uint32
	if ok, _, _ := procGetConsoleMode.Call(h, uintptr(unsafe.Pointer(&mode))); ok == 0 {
		return func() {}
	}
	if mode&enableVirtualTerminalProc != 0 {
		return func() {}
	}
	if ok, _, _ := procSetConsoleMode.Call(h, uintptr(mode|enableVirtualTerminalProc)); ok == 0 {
		return func() {}
	}
	old := mode
	return func() { _, _, _ = procSetConsoleMode.Call(h, uintptr(old)) }
}
