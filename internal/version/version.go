// Package version 保存构建期注入的版本信息。
package version

// Version 是 EasyWork 的**唯一版本来源**。
// - 本地/默认构建：使用此值。
// - release：由构建期 ldflags 注入 tag（-X github.com/EasyIndie/EasyWork/internal/version.Version=<tag>）。
// Bash 实现（legacy）在本地 checkout 时从本文件读取版本；VERSION 文件与脚本常量已删除。
// 见 DESIGN §12.5。
var Version = "0.2.1"

// Channel 为空表示正式 release；"dev" 表示本地 checkout / main 分支。
var Channel = ""

// APIDefault 是更新检查的默认 GitHub API。
const APIDefault = "https://api.github.com/repos/EasyIndie/EasyWork/releases/latest"
