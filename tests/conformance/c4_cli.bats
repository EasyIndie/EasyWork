#!/usr/bin/env bats
# C4 — CLI 与 JSON 输出（见 docs/spec/04-cli-json.md）

load helpers

@test "C4-status-json-exact" {
    ew_capture status --json --offline
    [ "$EW_RC" -eq 0 ]
    local mods
    if [ "${EW_ENGINE:-}" = "go" ]; then
        # 优先级序：shell(10) git(20) gh(25) vim(30) ai(50) glow(55) herdr(60) mole(65) ghostty(70) keepawake(75)
        mods='{"name":"shell","state":"absent","ok":false},{"name":"git","state":"absent","ok":false},{"name":"gh","state":"absent","ok":false},{"name":"vim","state":"absent","ok":false},{"name":"ai","state":"absent","ok":false},{"name":"glow","state":"absent","ok":false},{"name":"herdr","state":"absent","ok":false},{"name":"mole","state":"absent","ok":false},{"name":"ghostty","state":"absent","ok":false},{"name":"keepawake","state":"absent","ok":false}'
    else
        mods='{"name":"shell","state":"absent","ok":false},{"name":"git","state":"absent","ok":false},{"name":"gh","state":"absent","ok":false},{"name":"vim","state":"absent","ok":false},{"name":"ai-tools","state":"absent","ok":false}'
    fi
    local want
    local home_native
    home_native="$(native_path "$EASYWORK_HOME")"
    want="{\"ok\":true,\"command\":\"status\",\"data\":{\"config\":{\"path\":\"${home_native}/config.toml\",\"exists\":false,\"valid\":true},\"modules\":[${mods}],\"update\":{\"latest\":null,\"available\":false}},\"error\":null}"
    [ "$EW_OUT" = "$want" ]
}

@test "C4-list-order-is-registration-order" {
    ew_capture list --json --offline
    [ "$EW_RC" -eq 0 ]
    local want='{"ok":true,"command":"list","data":{"modules":['
    if [ "${EW_ENGINE:-}" = "go" ]; then
        # v2.x 增量：模块名 ai（别名 ai-tools）+ 子组件 + 可选工具（Bash 已冻结）
        want+='{"name":"ai","description":"安装 AI 编码 CLI（claude code / codex / pi）","priority":50,"components":['
        want+='{"name":"claude","description":"Anthropic Claude Code（npm: @anthropic-ai/claude-code）"},'
        want+='{"name":"codex","description":"OpenAI Codex CLI（npm: @openai/codex）"},'
        want+='{"name":"pi","description":"Pi coding agent（npm: @earendil-works/pi-coding-agent）"}]},'
        want+='{"name":"gh","description":"安装 GitHub CLI (gh)","priority":25},'
        want+='{"name":"ghostty","description":"Ghostty 终端（macOS / Linux）","priority":70,"optional":true},'
        want+='{"name":"git","description":"配置 Git 别名和身份","priority":20},'
        want+='{"name":"glow","description":"终端 Markdown 渲染 (glow)","priority":55,"optional":true},'
        want+='{"name":"herdr","description":"Agent 运行时 (herdr)","priority":60,"optional":true},'
        want+='{"name":"keepawake","description":"设备防休眠（长跑任务不中断）","priority":75,"optional":true},'
        want+='{"name":"mole","description":"macOS 清理与优化 (mole/mo)","priority":65,"optional":true},'
        want+='{"name":"shell","description":"配置 Shell 环境 (bash/zsh 适配)","priority":10},'
        want+='{"name":"vim","description":"配置 Vim IDE","priority":30}],'
    else
        want+='{"name":"ai-tools","description":"安装 AI 编码 CLI（claude code / codex / pi）","priority":50},'
        want+='{"name":"gh","description":"安装 GitHub CLI (gh)","priority":25},'
        want+='{"name":"git","description":"配置 Git 别名和身份","priority":20},'
        want+='{"name":"shell","description":"配置 Shell 环境 (bash/zsh 适配)","priority":10},'
        want+='{"name":"vim","description":"配置 Vim IDE","priority":30}],'
    fi
    want+='"update":{"latest":null,"available":false}},"error":null}'
    [ "$EW_OUT" = "$want" ]
}

@test "C4-doctor-check-order" {
    ew_capture doctor --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'"name":"curl"'* ]]
    [[ "$EW_OUT" == *'"name":"network"'* ]]
    # curl 必须先于 network
    local a b
    a="${EW_OUT%%\"name\":\"curl\"*}"
    b="${EW_OUT%%\"name\":\"network\"*}"
    [ ${#a} -lt ${#b} ]
}

@test "C4-json-keeps-stdout-pure" {
    ew_capture status --json --offline
    # stdout 必须只含一行 JSON，且无日志前缀
    [ "$(printf '%s' "$EW_OUT" | wc -l | tr -d ' ')" -eq 0 ]
    [[ "$EW_OUT" == "{"* ]]
    [[ "$EW_OUT" != *"●"* ]]
    [[ "$EW_OUT" != *"✓"* ]]
}

@test "C4-unknown-command-exits-1" {
    ew_capture definitely-not-a-command
    [ "$EW_RC" -eq 1 ]
}

# 退役前从 Bash e2e 迁入：ew init = shell + git，零交互，不装 vim。
@test "C4-init-installs-shell-and-git" {
    ew_capture init --offline
    [ "$EW_RC" -eq 0 ]
    grep -q '^\[shell\]' "$EASYWORK_HOME/manifest"
    grep -q '^\[git\]' "$EASYWORK_HOME/manifest"
    ! grep -q '^\[vim\]' "$EASYWORK_HOME/manifest"
    [ ! -e "$HOME/.vimrc" ]
}

# doctor 的电源策略自洽性检查（仅 macOS；pmset 矛盾组合容易"设了但没生效"）
@test "C7-doctor-sleep-policy-on-macos" {
    [ "$(uname -s)" = "Darwin" ] || skip "macOS only"
    ew_capture doctor --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'"name":"sleep-policy"'* ]]
    [[ "$EW_OUT" == *'displaysleep='* ]]
    [[ "$EW_OUT" == *'disksleep='* ]]
}

@test "C7-doctor-no-sleep-policy-off-macos" {
    [ "$(uname -s)" != "Darwin" ] || skip "non-macOS only"
    ew_capture doctor --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" != *'"name":"sleep-policy"'* ]]
}
