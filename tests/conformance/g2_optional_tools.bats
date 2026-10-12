#!/usr/bin/env bats
# G2 — 可选工具（glow / herdr / mole / ghostty）：平台门控 + 默认不装（仅 Go）
#
# 规则：不安装 GUI 应用，**终端模拟器除外**（Ghostty 属允许项）。
# Bash 已冻结；本特性仅 Go 实现。

load helpers

@test "G2-list-marks-optional-tools" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture list --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'{"name":"glow","description":"终端 Markdown 渲染 (glow)","priority":55,"optional":true}'* ]]
    [[ "$EW_OUT" == *'{"name":"herdr","description":"Agent 运行时 (herdr)","priority":60,"optional":true}'* ]]
    [[ "$EW_OUT" == *'{"name":"mole","description":"macOS 清理与优化 (mole/mo)","priority":65,"optional":true}'* ]]
    [[ "$EW_OUT" == *'{"name":"ghostty","description":"Ghostty 终端（macOS / Linux）","priority":70,"optional":true}'* ]]
    # 核心模块不带 optional 字段
    [[ "$EW_OUT" == *'{"name":"gh","description":"安装 GitHub CLI (gh)","priority":25}'* ]]
}

@test "G2-list-human-shows-optional-marker" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture list
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"可选"* ]]
    [[ "$EW_OUT" == *"glow"* ]]
    [[ "$EW_OUT" == *"herdr"* ]]
    [[ "$EW_OUT" == *"mole"* ]]
    [[ "$EW_OUT" == *"ghostty"* ]]
}

@test "G2-default-install-skips-optional" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"配置 shell..."* ]]
    for m in glow herdr mole ghostty; do
        [[ "$EW_OUT" != *"${m}"* ]]
    done
}

@test "G2-explicit-install-runs-dry-run" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    # glow 全平台支持
    ew_capture install glow --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"将安装 glow"* ]]
}

@test "G2-unsupported-platform-is-skipped" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    case "$(uname -s)" in
        Linux)
            # mole 不支持 Linux（macOS + 官方 Windows CLI）
            ew_capture install mole --dry-run --yes
            [ "$EW_RC" -eq 0 ]
            [[ "$EW_OUT" == *"当前平台不支持"* ]]
            [[ "$EW_OUT" != *"将安装 mole"* ]]
            # glow / herdr / ghostty 支持 Linux
            ew_capture install glow herdr ghostty --dry-run --yes
            [[ "$EW_OUT" == *"将安装 glow"* ]]
            [[ "$EW_OUT" == *"将安装 herdr"* ]]
            [[ "$EW_OUT" == *"将安装 ghostty"* ]]
            ;;
        Darwin)
            # mole / glow / herdr / ghostty 均有支持版本
            ew_capture install mole glow herdr ghostty --dry-run --yes
            [[ "$EW_OUT" == *"将安装 mole"* ]]
            [[ "$EW_OUT" == *"将安装 glow"* ]]
            [[ "$EW_OUT" == *"将安装 herdr"* ]]
            [[ "$EW_OUT" == *"将安装 ghostty"* ]]
            ;;
        MINGW* | MSYS* | CYGWIN*)
            # ghostty（终端模拟器）不支持 Windows；mole/glow/herdr 支持
            ew_capture install ghostty --dry-run --yes
            [[ "$EW_OUT" == *"当前平台不支持"* ]]
            [[ "$EW_OUT" != *"将安装 ghostty"* ]]
            ew_capture install mole glow herdr --dry-run --yes
            [[ "$EW_OUT" == *"将安装 mole"* ]]
            ;;
        *)
            skip "unknown platform: $(uname -s)"
            ;;
    esac
}
