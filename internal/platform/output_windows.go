//go:build windows

package platform

import (
	"io"
	"os"
	"strings"
	"unsafe"
)

var (
	procWideCharToMultiByte = kernel32.NewProc("WideCharToMultiByte")
	procGetFileType         = kernel32.NewProc("GetFileType")
)

const fileTypeChar = 2

// ConsoleOutput 针对 Windows 的编码现实做适配：
//
//   - 直接写控制台：conhost/Windows Terminal 能正确渲染 UTF-8（无需转码）；
//   - 被管道/重定向且控制台代码页不是 UTF-8（中文系统默认 936）：
//     PowerShell 5.1 与 cmd 会按 OEM 代码页解码管道字节，UTF-8 中文因此乱码。
//     此时把输出转成系统 ANSI 代码页，与 `dir`、`chcp` 等原生工具行为一致。
//
// 环境变量 EASYWORK_OUTPUT_ENCODING 可覆盖：`utf8` 强制不转码（CI/脚本用），
// `oem` 强制转码。--json 输出不经过本函数（必须是合法 UTF-8）。
func ConsoleOutput(w io.Writer) io.Writer {
	mode := strings.ToLower(strings.TrimSpace(os.Getenv("EASYWORK_OUTPUT_ENCODING")))
	if mode == "utf8" || mode == "utf-8" {
		return w
	}
	cp := OriginalConsoleCodePage()
	if cp == 0 || cp == utf8CodePage {
		return w
	}
	if mode == "" && isConsoleWriter(w) {
		return w
	}
	return &ansiWriter{w: w, cp: uintptr(cp)}
}

func isConsoleWriter(w io.Writer) bool {
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	r, _, _ := procGetFileType.Call(f.Fd())
	return r == fileTypeChar
}

// ansiWriter 把 UTF-8 文本转成指定代码页（WideCharToMultiByte，零依赖）。
type ansiWriter struct {
	w  io.Writer
	cp uintptr
}

func (a *ansiWriter) Write(p []byte) (int, error) {
	wide, err := toUTF16(p)
	if err != nil || len(wide) == 0 {
		return a.w.Write(p)
	}
	need, _, _ := procWideCharToMultiByte.Call(a.cp, 0,
		uintptr(unsafe.Pointer(&wide[0])), uintptr(len(wide)), 0, 0, 0, 0)
	if need == 0 {
		return a.w.Write(p)
	}
	buf := make([]byte, need)
	if ok, _, _ := procWideCharToMultiByte.Call(a.cp, 0,
		uintptr(unsafe.Pointer(&wide[0])), uintptr(len(wide)),
		uintptr(unsafe.Pointer(&buf[0])), need, 0, 0); ok == 0 {
		return a.w.Write(p)
	}
	if _, werr := a.w.Write(buf); werr != nil {
		return 0, werr
	}
	return len(p), nil
}

// toUTF16 把 UTF-8 字节转成 UTF-16 码元（不含结尾 NUL）。
func toUTF16(p []byte) ([]uint16, error) {
	s := strings.ToValidUTF8(string(p), "\uFFFD")
	out := make([]uint16, 0, len(s))
	for _, r := range s {
		if r < 0x10000 {
			out = append(out, uint16(r))
			continue
		}
		r -= 0x10000
		out = append(out, uint16(0xD800+(r>>10)), uint16(0xDC00+(r&0x3FF)))
	}
	return out, nil
}
