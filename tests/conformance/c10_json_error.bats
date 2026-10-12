#!/usr/bin/env bats
# C10 — JSON 错误信封（见 docs/spec/04-cli-json.md）

load helpers

@test "C10-json-unknown-command-envelope-exact" {
    ew_capture --json bogus
    [ "$EW_RC" -eq 1 ]
    [ "$EW_OUT" = '{"ok":false,"command":"bogus","data":null,"error":{"code":1,"message":"未知命令: bogus"}}' ]
}

@test "C10-json-install-unknown-module-envelope-exact" {
    ew_capture --json install nope
    [ "$EW_RC" -eq 1 ]
    [ "$EW_OUT" = '{"ok":false,"command":"install","data":null,"error":{"code":1,"message":"未知组件: nope"}}' ]
}

@test "C10-json-config-usage-envelope" {
    ew_capture --json config get
    [ "$EW_RC" -eq 1 ]
    [[ "$EW_OUT" == *'"ok":false'* ]]
    [[ "$EW_OUT" == *'"data":null'* ]]
    [[ "$EW_OUT" == *'"code":1'* ]]
}

@test "C10-json-update-offline-envelope" {
    ew_capture --json update --offline
    [ "$EW_RC" -eq 3 ]
    [[ "$EW_OUT" == *'"ok":false'* ]]
    [[ "$EW_OUT" == *'"code":3'* ]]
}

@test "C10-json-success-has-null-error" {
    ew_capture --json status --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *'"ok":true'* ]]
    [[ "$EW_OUT" == *'"error":null'* ]]
}

@test "C10-json-error-does-not-create-state" {
    ew_capture --json install nope
    [ ! -f "$EASYWORK_HOME/config.toml" ]
    [ ! -f "$EASYWORK_HOME/manifest" ]
}
