#!/usr/bin/env bats
# C3 — 安装状态 manifest（见 docs/spec/03-manifest.md）

load helpers

@test "C3-status-reflects-installed-states" {
    write_manifest << 'EOF'
# EasyWork Manifest — auto-generated, do not edit
schema_version=1
easywork_version=0.1.0
install_date=2026-06-12T10:15:30+0800

[shell]
installed=true

[git]
installed=true

[vim]
installed=failed
failed_at=2026-06-12T10:15:30+0800
EOF
    ew_capture status --json --offline
    [[ "$EW_OUT" == *'"name":"shell","state":"true","ok":true'* ]]
    [[ "$EW_OUT" == *'"name":"git","state":"true","ok":true'* ]]
    [[ "$EW_OUT" == *'"name":"vim","state":"failed","ok":false'* ]]
    [[ "$EW_OUT" == *'"name":"gh","state":"absent","ok":false'* ]]
}

@test "C3-version-lists-installed-sections" {
    write_manifest << 'EOF'
schema_version=1
easywork_version=0.1.0
install_date=2026-06-12T10:15:30+0800
[shell]
installed=true
[git]
installed=true
[vim]
installed=false
EOF
    ew_capture version --json --offline
    [[ "$EW_OUT" == *'"installed":["shell","git"]'* ]]
}

@test "C3-manifest-tolerates-crlf" {
    printf 'schema_version=1\r\neasywork_version=0.1.0\r\n[shell]\r\ninstalled=true\r\n' \
        > "$EASYWORK_HOME/manifest"
    ew_capture status --json --offline
    [[ "$EW_OUT" == *'"name":"shell","state":"true","ok":true'* ]]
}
