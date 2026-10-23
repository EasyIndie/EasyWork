#!/usr/bin/env bats
# C5 — 模块接口与注册（见 docs/spec/05-module-interface.md）

load helpers

@test "C5-list-exposes-all-modules" {
    ew_capture list --json --offline
    local mods
    if [ "${EW_ENGINE:-}" = "go" ]; then
        mods="ai gh ghostty git glow herdr mole shell vim"
    else
        mods="shell git gh vim ai-tools"
    fi
    local m
    for m in $mods; do
        [[ "$EW_OUT" == *"\"name\":\"${m}\""* ]]
    done
}

@test "C5-module-shortcut-is-rejected" {
    ew_capture git
    [ "$EW_RC" -eq 1 ]
}

@test "C5-status-orders-by-priority" {
    ew_capture status --json --offline
    # shell(10) < git(20) < gh(25) < vim(30) < ai(50) < glow(55) < herdr(60) < mole(65) < ghostty(70)
    local order
    if [ "${EW_ENGINE:-}" = "go" ]; then
        order="shell git gh vim ai glow herdr mole ghostty"
    else
        order="shell git gh vim ai-tools"
    fi
    local pat=""
    local m
    for m in $order; do
        pat="${pat}*\"name\":\"${m}\""
    done
    [[ "$EW_OUT" == ${pat}* ]]
}

# 退役前从 Bash e2e 迁入：显式安装单个模块只应用该模块。
@test "C5-install-single-module" {
    ew_capture install vim --yes --offline
    [ "$EW_RC" -eq 0 ]
    grep -q '^\[vim\]' "$EASYWORK_HOME/manifest"
    ! grep -q '^\[git\]' "$EASYWORK_HOME/manifest"
    ! grep -q '^\[shell\]' "$EASYWORK_HOME/manifest"
    [ ! -s "$HOME/.gitconfig" ]
}
