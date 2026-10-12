#!/usr/bin/env bats
# C9 — update 自升级（见 docs/spec/04-cli-json.md）

load helpers

@test "C9-update-offline-exits-3" {
    ew_capture update --offline
    [ "$EW_RC" -eq 3 ]
}
