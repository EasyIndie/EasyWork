//go:build windows

package platform

import (
	"bytes"
	"os"
	"testing"
)

func TestToUTF16IncludesSurrogatePairs(t *testing.T) {
	// BMP 中文 + 非 BMP 表情（代理对）
	wide, err := toUTF16([]byte("中😀"))
	if err != nil {
		t.Fatalf("转换失败: %v", err)
	}
	if len(wide) != 3 {
		t.Fatalf("应为 1+2 个码元，得到 %d: %v", len(wide), wide)
	}
	if wide[0] != 0x4E2D || wide[1] != 0xD83D || wide[2] != 0xDE00 {
		t.Fatalf("码元不正确: %#x", wide)
	}
}

func TestANSIMultiByteForCP936(t *testing.T) {
	if OriginalConsoleCodePage() != 936 {
		t.Skip("仅中文代码页环境验证")
	}
	var buf bytes.Buffer
	w := &ansiWriter{w: &buf}
	if _, err := w.Write([]byte("关闭")); err != nil {
		t.Fatal(err)
	}
	// GBK 编码「关闭」= B9 D8 B1 D5
	if !bytes.Equal(buf.Bytes(), []byte{0xB9, 0xD8, 0xB1, 0xD5}) {
		t.Fatalf("GBK 字节不正确: % x", buf.Bytes())
	}
}

func TestConsoleOutputHonorsUTF8Override(t *testing.T) {
	t.Setenv("EASYWORK_OUTPUT_ENCODING", "utf8")
	w := ConsoleOutput(os.Stdout)
	if w != os.Stdout {
		t.Fatal("utf8 覆盖时应原样返回 writer")
	}
}
