#!/usr/bin/env bats
# C1 — 状态根 EASYWORK_HOME（见 docs/spec/01-home.md）

load helpers

@test "C1-status-reports-config-path-under-home" {
    local home_native
    home_native="$(native_path "$EASYWORK_HOME")"
    ew_capture status --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"\"path\":\"${home_native}/config.toml\""* ]]
}

@test "C1-home-override-is-honored" {
    local alt="$TEST_HOME/alt-home"
    local alt_native
    alt_native="$(native_path "$alt")"
    mkdir -p "$alt"
    EASYWORK_HOME="$alt" ew_capture status --json --offline
    [ "$EW_RC" -eq 0 ]
    [[ "$EW_OUT" == *"\"path\":\"${alt_native}/config.toml\""* ]]
}

@test "C1-config-path-tracks-home-not-hardcoded" {
    local alt="$TEST_HOME/custom"
    mkdir -p "$alt"
    printf 'schema_version = 1\n' > "$alt/config.toml"
    EASYWORK_HOME="$alt" ew_capture status --json --offline
    [[ "$EW_OUT" == *"\"exists\":true"* ]]
}
