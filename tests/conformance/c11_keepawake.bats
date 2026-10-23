#!/usr/bin/env bats
# C11 — 设备防休眠 keepawake（契约八草案，仅 Go 引擎）
#
# 规格见 docs/spec/08-keepawake.md。
# 这些用例**不得**真正改动宿主电源状态：只验证只读探测、幂等 off 与 --dry-run。

load helpers

@test "C11-status-json-inactive" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture keepawake status --json
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'"ok":true'* ]]
    [[ "$EW_OUT" == *'"command":"keepawake"'* ]]
    [[ "$EW_OUT" == *'"state":"inactive"'* ]]
    [[ "$EW_OUT" == *'"enabled":false'* ]]
    [[ "$EW_OUT" == *'"mode":"ac"'* ]]
    [[ "$EW_OUT" == *'"platform":'* ]]
}

@test "C11-status-json-has-no-logs-on-stdout" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture keepawake status --json
    [ "$EW_RC" -eq 0 ]
    # stdout 必须是单个 JSON 信封：首字符 { 且不含 ANSI
    [ "${EW_OUT:0:1}" = "{" ]
    [[ "$EW_OUT" != *$'\033'* ]]
}

@test "C11-off-idempotent" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture keepawake off
    [ "$EW_RC" -eq 0 ]
    ew_capture keepawake off
    [ "$EW_RC" -eq 0 ]
    # off 必须把期望状态落盘为关闭（否则 apply 会自己开回来）
    grep -q 'enabled = "false"' "$EASYWORK_HOME/config.toml"
}

@test "C11-on-dry-run-does-not-start" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture keepawake on --dry-run
    [ "$EW_RC" -eq 0 ]
    [ ! -f "$EASYWORK_HOME/run/keepawake.json" ]
}

@test "C11-on-rejects-unknown-flag" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture keepawake on --bogus
    [ "$EW_RC" -eq 1 ]
}

@test "C11-unknown-subcommand" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture keepawake bouncing
    [ "$EW_RC" -eq 1 ]
}

@test "C11-list-marks-optional" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture list --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'"name":"keepawake"'* ]]
    [[ "$EW_OUT" == *'设备防休眠'* ]]
}

@test "C11-help-lists-command" {
    [ "${EW_ENGINE:-}" = "go" ] || skip "Go-only feature (v2.x)"
    ew_capture help
    [[ "$EW_OUT" == *"keepawake"* ]]
}
