#!/usr/bin/env bats
# G1 — 细粒度子组件选择（v2.x，仅 Go 引擎）
#
# 背景：Bash 实现已冻结，仅作迁移期等价 oracle；本特性为 Go 起新增，故
# 通过 $EW_ENGINE 守卫，仅在 go 引擎下运行。契约见 docs/spec/05、DESIGN §13。

load helpers

@test "G1-list-json-exposes-components" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture list --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'"name":"ai"'* ]]
    [[ "$EW_OUT" == *'"components":[{"name":"claude"'* ]]
    [[ "$EW_OUT" == *'"name":"codex"'* ]]
    [[ "$EW_OUT" == *'"name":"pi"'* ]]
}

@test "G1-list-human-shows-components" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture list
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"  ai "* ]]
    [[ "$EW_OUT" == *"claude"* ]]
    [[ "$EW_OUT" == *"codex"* ]]
    [[ "$EW_OUT" == *"pi"* ]]
}

@test "G1-install-single-component-dry-run" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install ai/claude --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"claude"* ]]
    [[ "$EW_OUT" != *"codex"* ]]
    [[ "$EW_OUT" != *"pi"* ]]
}

@test "G1-install-shorthand-component" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install claude --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"将安装 AI 编码 CLI: claude"* ]]
    [[ "$EW_OUT" != *"codex"* ]]
}

@test "G1-install-space-separated-subset" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install ai/codex ai/pi --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"codex, pi"* ]]
    [[ "$EW_OUT" != *"claude"* ]]
}

@test "G1-install-space-separated-shorthand" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install claude pi --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"claude, pi"* ]]
    [[ "$EW_OUT" != *"codex"* ]]
}

@test "G1-config-default-subset" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture config set ai.tools "claude pi"
    [ "$EW_RC" -eq 0 ]
    ew_capture install ai --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"claude, pi"* ]]
    [[ "$EW_OUT" != *"codex"* ]]
}

@test "G1-install-whole-set" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install ai --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"claude, codex, pi"* ]]
}

@test "G1-install-executes-only-selected" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    # Windows: 无扩展名的 bash mock 不被 Go LookPath(PATHEXT) 识别，易误用真实 npm
    is_windows && skip "Windows: 无法用无扩展名脚本 mock npm"
    mkdir -p "$TEST_HOME/bin"
    cat > "$TEST_HOME/bin/npm" << 'NPM'
#!/usr/bin/env bash
echo "$*" >> "$NPM_LOG"
NPM
    chmod +x "$TEST_HOME/bin/npm"
    export NPM_LOG="$TEST_HOME/npm.log"
    : > "$NPM_LOG"
    export PATH="$TEST_HOME/bin:$PATH"

    ew_capture install ai/claude --yes
    [ "$EW_RC" -eq 0 ]
    grep -q 'selected=claude' "$EASYWORK_HOME/manifest"
    grep -q 'tools=claude' "$EASYWORK_HOME/manifest"
    ! grep -q 'codex' "$EASYWORK_HOME/manifest"
    # 若触发 npm，则不得安装未选中的包
    ! grep -q '@openai/codex' "$NPM_LOG"
}

@test "G1-legacy-alias-and-section-still-work" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    # 旧模块名作为别名仍可安装
    ew_capture install ai-tools/claude --dry-run --yes
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"claude"* ]]
    # 旧 manifest 节 [ai-tools] 仍被识别为 ai 已安装
    write_manifest << 'EOF'
schema_version=1
easywork_version=0.1.0
[ai-tools]
installed=true
tools=claude
EOF
    ew_capture status --json --offline
    [[ "$EW_OUT" == *'"name":"ai","state":"true","ok":true'* ]]
    ew_capture version --json --offline
    [[ "$EW_OUT" == *'"installed":["ai"]'* ]]
}

@test "G1-unknown-component-exits-1" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture install ai/bogus
    [ "$EW_RC" -eq 1 ]
    [[ "$EW_ERR" == *"未知子工具"* ]]
}
