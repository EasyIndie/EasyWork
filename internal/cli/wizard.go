package cli

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// wizardGitIdentity 是 install 的交互增强：若未检测到 Git 身份且处于交互终端，
// 最多询问 2 个问题并写回 config.toml。设计原则见 DESIGN §1.5：
// 「非交互是默认，交互是增强」「全程 ≤2 问」「身份缺失不阻塞」。
func (a *App) wizardGitIdentity() {
	if a.Yes || a.JSON || a.DryRun || !isTerminal(os.Stdin) {
		return
	}
	if a.Config.Get("git.identities.personal.name", "") != "" {
		return
	}
	if gitGlobalName() != "" {
		return
	}

	a.Log.Info("未检测到 Git 身份，可现在设置（直接回车跳过，稍后可用 ew config set 设置）")
	reader := bufio.NewReader(os.Stdin)

	name := strings.TrimSpace(readLine(reader, "  Git 用户名: "))
	if name == "" {
		a.Log.Info("已跳过 Git 身份设置（仅配置别名）")
		return
	}
	email := strings.TrimSpace(readLine(reader, "  Git 邮箱: "))

	if err := a.Config.Set("git.identities.personal.name", name); err != nil {
		a.Log.Warn("写入 Git 用户名失败: " + err.Error())
	}
	if email != "" {
		if !looksLikeEmail(email) {
			a.Log.Warn("邮箱格式看起来不正确，仍将写入: " + email)
		}
		if err := a.Config.Set("git.identities.personal.email", email); err != nil {
			a.Log.Warn("写入 Git 邮箱失败: " + err.Error())
		}
	}
	a.Log.Success("已记录 Git 身份")
}

// readLine 打印提示并从 reader 读取一行。
func readLine(reader *bufio.Reader, prompt string) string {
	fmt.Fprint(os.Stderr, prompt)
	line, err := reader.ReadString('\n')
	if err != nil && line == "" {
		return ""
	}
	return strings.TrimRight(line, "\r\n")
}

// looksLikeEmail 做基本格式校验（不追求 RFC 完备）。
func looksLikeEmail(s string) bool {
	at := strings.IndexByte(s, '@')
	if at <= 0 || at == len(s)-1 {
		return false
	}
	domain := s[at+1:]
	dot := strings.LastIndexByte(domain, '.')
	return dot > 0 && dot < len(domain)-1
}

// gitGlobalName 返回 `git config --global user.name`，无则空串。
func gitGlobalName() string {
	out, err := exec.Command("git", "config", "--global", "user.name").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
