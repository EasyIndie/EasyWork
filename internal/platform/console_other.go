//go:build !windows

package platform

// EnableUTF8Console 在非 Windows 平台是 no-op：终端本身按 UTF-8 解析。
func EnableUTF8Console() func() { return func() {} }

// ConsoleCodePage 在非 Windows 平台无意义，返回 0。
func ConsoleCodePage() int { return 0 }

// OriginalConsoleCodePage 在非 Windows 平台无意义，返回 0。
func OriginalConsoleCodePage() int { return 0 }
