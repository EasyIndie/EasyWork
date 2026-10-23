//go:build !windows

package platform

import (
	"os"
	"testing"
)

// 非 Windows 平台不得对输出做任何转码。
func TestConsoleOutputIsIdentity(t *testing.T) {
	if got := ConsoleOutput(os.Stdout); got != os.Stdout {
		t.Fatal("非 Windows 平台应原样返回 writer")
	}
	if ConsoleCodePage() != 0 || OriginalConsoleCodePage() != 0 {
		t.Fatal("非 Windows 平台代码页应为 0")
	}
}
