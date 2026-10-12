#!/usr/bin/env bats
# C2 — 声明式配置 config.toml（见 docs/spec/02-config-toml.md）

load helpers

@test "C2-set-then-get-roundtrip" {
    ew_capture config set git.identities.personal.name 张三
    [ "$EW_RC" -eq 0 ]
    ew_capture config get git.identities.personal.name
    [ "$EW_RC" -eq 0 ]
    [ "$EW_OUT" = "张三" ]
}

@test "C2-get-missing-returns-default-empty" {
    ew_capture config get nope.key
    [ "$EW_RC" -eq 0 ]
    [ -z "$EW_OUT" ]
}

@test "C2-get-bool-normalizes" {
    write_config << 'EOF'
schema_version = 1
[shell]
a = true
b = 1
c = yes
d = off
EOF
    ew_capture config get shell.a
    [ "$EW_OUT" = "true" ]
    ew_capture config get shell.c
    [ "$EW_OUT" = "yes" ]
}

@test "C2-valid-accepts-schema-1" {
    write_config << 'EOF'
schema_version = 1
EOF
    ew_capture status --json --offline
    [[ "$EW_OUT" == *"\"valid\":true"* ]]
}

@test "C2-valid-rejects-other-schema" {
    write_config << 'EOF'
schema_version = 2
EOF
    ew_capture status --json --offline
    [[ "$EW_OUT" == *"\"valid\":false"* ]]
}

@test "C2-set-preserves-unrelated-keys" {
    write_config << 'EOF'
schema_version = 1
# keep me
[git]
scope = "global"
EOF
    ew_capture config set git.identity personal
    grep -q '# keep me' "$EASYWORK_HOME/config.toml"
    grep -q 'scope = "global"' "$EASYWORK_HOME/config.toml"
    ew_capture config get git.identity
    [ "$EW_OUT" = "personal" ]
}

@test "C2-quoted-value-unescapes" {
    write_config << 'EOF'
schema_version = 1
[shell]
greeting = "say \"hi\" \\ bye"
EOF
    ew_capture config get shell.greeting
    [ "$EW_OUT" = 'say "hi" \ bye' ]
}

@test "C2-set-top-level-key" {
    write_config << 'EOF'
schema_version = 1
[shell]
a = true
EOF
    ew_capture config set mykey hello
    [ "$EW_RC" -eq 0 ]
    ew_capture config get mykey
    [ "$EW_OUT" = "hello" ]
    ! grep -q '^\[\]$' "$EASYWORK_HOME/config.toml"
}

@test "C2-set-top-level-key-replaces-in-place" {
    write_config << 'EOF'
schema_version = 1
[shell]
a = true
EOF
    ew_capture config set schema_version 1
    [ "$EW_RC" -eq 0 ]
    [ "$(grep -c '^schema_version' "$EASYWORK_HOME/config.toml")" -eq 1 ]
}
