package engine

import (
	"bytes"
	"encoding/json"
	"os"
)

// Encode 生成字节级固定的紧凑 JSON（无 HTML 转义，末尾换行）——格式本身即契约四。
func Encode(v any) []byte {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		os.Stderr.WriteString("easywork: JSON 编码失败: " + err.Error() + "\n")
		return nil
	}
	return buf.Bytes()
}
