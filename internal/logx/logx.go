// Package logx 提供日志与数据分流（契约四：--json 时日志走 stderr）。
package logx

import (
	"fmt"
	"io"
	"os"
)

// Logger 负责人类可读日志；JSON 模式下信息类日志改走 stderr。
type Logger struct {
	JSON    bool
	Verbose bool
	Color   bool
	Out     io.Writer
	Err     io.Writer
}

// New 返回默认 Logger。
func New() *Logger {
	color := false
	if fi, err := os.Stdout.Stat(); err == nil && (fi.Mode()&os.ModeCharDevice) != 0 {
		if os.Getenv("NO_COLOR") == "" && os.Getenv("TERM") != "dumb" {
			color = true
		}
	}
	return &Logger{Out: os.Stdout, Err: os.Stderr, Color: color}
}

const (
	cReset  = "\033[0m"
	cRed    = "\033[31m"
	cGreen  = "\033[32m"
	cYellow = "\033[33m"
	cCyan   = "\033[36m"
)

func (l *Logger) paint(code, s string) string {
	if !l.Color {
		return s
	}
	return code + s + cReset
}

func (l *Logger) dataWriter() io.Writer {
	if l.JSON {
		return l.Err
	}
	return l.Out
}

// Info 打印信息（JSON 模式走 stderr）。
func (l *Logger) Info(msg string) {
	fmt.Fprintf(l.dataWriter(), "  %s %s\n", l.paint(cCyan, "●"), msg)
}

// Success 打印成功信息（JSON 模式走 stderr）。
func (l *Logger) Success(msg string) {
	fmt.Fprintf(l.dataWriter(), "  %s %s\n", l.paint(cGreen, "✓"), msg)
}

// Warn 打印警告（始终 stderr）。
func (l *Logger) Warn(msg string) { fmt.Fprintf(l.Err, "  %s %s\n", l.paint(cYellow, "!"), msg) }

// Error 打印错误（始终 stderr）。
func (l *Logger) Error(msg string) { fmt.Fprintf(l.Err, "  %s %s\n", l.paint(cRed, "✗"), msg) }

// Debug 仅在 --verbose 时打印到 stderr。
func (l *Logger) Debug(msg string) {
	if l.Verbose {
		fmt.Fprintf(l.Err, "  %s %s\n", l.paint(cCyan, "[DEBUG]"), msg)
	}
}
