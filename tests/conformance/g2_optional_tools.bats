#!/usr/bin/env bats
# G2 — 可选 CLI 工具（mole / herdr / glow）：平台门控 + 默认不装（仅 Go）
#
# 注意：仅安装 CLI 工具，不安装 GUI 应用。Bash 已冻结；本特性仅 Go 实现。

load helpers

@test "G2-list-marks-optional-tools" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture list --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'{"name":"glow","description":"终端 Markdown 渲染 (glow)","priority":55,"optional":true}'* ]]
    [[ "$EW_OUT" == *'{"name":"herdr","description":"Agent 运行时 (herdr)","priority":60,"optional":true}'* ]]
    [[ "$EW_OUT" == *'{"name":"mole","description":"macOS 清理与优化 (mole/mo)","priority":65,"optional":true}'* ]]
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
}

@test "G2-default-install-skips-optional" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"配置 shell..."* ]]
    for m in glow herdr mole; do
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
            # glow / herdr 支持 Linux
            ew_capture install glow herdr --dry-run --yes
            [[ "$EW_OUT" == *"将安装 glow"* ]]
            [[ "$EW_OUT" == *"将安装 herdr"* ]]
            ;;
        Darwin | MINGW* | MSYS* | CYGWIN*)
            # mole / glow / herdr 均有支持版本
            ew_capture install mole glow herdr --dry-run --yes
            [[ "$EW_OUT" == *"将安装 mole"* ]]
            [[ "$EW_OUT" == *"将安装 glow"* ]]
            [[ "$EW_OUT" == *"将安装 herdr"* ]]
            ;;
        *)
            skip "unknown platform: $(uname -s)"
            ;;
    esac
}
