#!/usr/bin/env bats
# C6 — Managed section 文件协议（见 docs/spec/06-managed-section.md）

load helpers

@test "C6-install-writes-managed-section-and-backup" {
    # 预置用户内容，验证备份 + 前置注入
    printf '# user content\n[user]\n    name = bob\n' > "$HOME/.gitconfig"
    ew_capture install git --yes --offline
    [ "$EW_RC" -eq 0 ]
    grep -q 'EasyWork managed section begin' "$HOME/.gitconfig"
    grep -q 'EasyWork managed section end' "$HOME/.gitconfig"
    grep -q '# user content' "$HOME/.gitconfig" # 用户内容保留
    ls "$HOME"/.gitconfig.bak.* > /dev/null 2>&1
}

@test "C6-install-is-idempotent" {
    ew_capture install git --yes --offline
    [ "$EW_RC" -eq 0 ]
    local before after
    before="$(cat "$HOME/.gitconfig")"
    ew_capture install git --yes --offline
    [ "$EW_RC" -eq 0 ]
    after="$(cat "$HOME/.gitconfig")"
    [ "$before" = "$after" ]
}

@test "C6-uninstall-removes-managed-section" {
    ew_capture install git --yes --offline
    grep -q 'EasyWork managed section begin' "$HOME/.gitconfig"
    ew_capture uninstall git --yes --offline
    [ "$EW_RC" -eq 0 ]
    ! grep -q 'EasyWork managed section begin' "$HOME/.gitconfig"
}

@test "C6-uninstall-restores-backup" {
    printf '# original\n[user]\n    name = alice\n' > "$HOME/.gitconfig"
    ew_capture install git --yes --offline
    ew_capture uninstall git --yes --offline
    [ "$EW_RC" -eq 0 ]
    grep -q '# original' "$HOME/.gitconfig"
    ! grep -q 'EasyWork managed section' "$HOME/.gitconfig"
}

@test "C6-shell-config-managed" {
    local target
    target="$(shell_target)"
    ew_capture install shell --yes --offline
    [ "$EW_RC" -eq 0 ]
    grep -q 'EasyWork managed section begin' "$target"
    ew_capture uninstall shell --yes --offline
    [ "$EW_RC" -eq 0 ]
    ! grep -q 'EasyWork managed section begin' "$target" 2> /dev/null
}

@test "C6-git-config-full-alias-set" {
    ew_capture install git --yes --offline
    [ "$EW_RC" -eq 0 ]
    grep -q 'lgtg = log --oneline --tags' "$HOME/.gitconfig"
    grep -q 'sh = !git --no-pager show HEAD' "$HOME/.gitconfig"
}

@test "C6-git-preserves-existing-identity" {
    printf '# >>> EasyWork managed section begin (v0.1.0) >>>\n[user]\n    name = Pre User\n    email = pre@example.com\n# <<< EasyWork managed section end <<<\n' > "$HOME/.gitconfig"
    ew_capture install git --yes --offline
    [ "$EW_RC" -eq 0 ]
    grep -q 'name = Pre User' "$HOME/.gitconfig"
    grep -q 'lgtg = log --oneline --tags' "$HOME/.gitconfig"
}
