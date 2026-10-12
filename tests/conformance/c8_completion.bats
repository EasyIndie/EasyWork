#!/usr/bin/env bats
# C8 — shell 补全（见 docs/spec/04-cli-json.md、07-cross-platform.md）

load helpers

@test "C8-completion-setup-injects-and-status" {
    local rc
    rc="$(completion_rc)"
    ew_capture completion setup
    [ "$EW_RC" -eq 0 ]
    [ -f "$EASYWORK_HOME/completions/easywork.bash" ]
    grep -q '# EasyWork completion' "$rc"

    ew_capture completion status
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"easywork.bash"* ]]
}

@test "C8-completion-remove-cleans-up" {
    local rc
    rc="$(completion_rc)"
    ew_capture completion setup
    ew_capture completion remove
    [ "$EW_RC" -eq 0 ]
    [ ! -f "$EASYWORK_HOME/completions/easywork.bash" ]
    ! grep -q '# EasyWork completion' "$rc"
}

@test "C8-completion-setup-is-idempotent" {
    local rc first
    rc="$(completion_rc)"
    ew_capture completion setup
    first="$(cat "$rc")"
    ew_capture completion setup
    [ "$(cat "$rc")" = "$first" ]
    [ "$(grep -c '# EasyWork completion' "$rc")" -eq 1 ]
}

@test "C8-completion-unknown-subcommand-exits-1" {
    ew_capture completion bogus
    [ "$EW_RC" -eq 1 ]
}
