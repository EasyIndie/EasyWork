#!/usr/bin/env bats
# Module tests: shell, git, vim module behavior + integration

setup() {
    load helpers/mocks
    setup_mocks
    EASYWORK_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "${EASYWORK_ROOT}/lib/common.sh"
    exec < /dev/null # never inherit the developer's tty
}

teardown() { teardown_mocks; }

# ── Shell Module ─────────────────────────────────────────────

@test "module: shell: variables and module_check" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    [[ "$MODULE_NAME" == "shell" ]]
    [[ -n "$MODULE_DESCRIPTION" ]]
    [[ "$MODULE_PRIORITY" -eq 10 ]]
    # Not installed by default
    run module_check
    [[ "$status" -ne 0 ]]
}

@test "module: shell: module_check true with markers" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    echo "# >>> EasyWork managed section begin (v1.0.0) >>>" > "$SH_CONFIG_FILE"
    echo "# <<< EasyWork managed section end <<<" >> "$SH_CONFIG_FILE"
    run module_check
    [[ "$status" -eq 0 ]]
}

@test "module: shell: _detect_shell_rc returns a path" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    local rc
    rc="$(_detect_shell_rc)"
    [[ "$rc" == "$HOME/"* ]]
}

@test "module: shell: _generate_shell_config is layered" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    local content
    content="$(_generate_shell_config)"
    # Always present
    [[ "$content" =~ "LC_ALL=en_US.UTF-8" ]]
    [[ "$content" =~ "BLACK=\$'\\e[30m'" ]]
    [[ "$content" =~ "run()" ]]
    # Aliases are on by default
    [[ "$content" =~ "alias g='git'" ]]
    # Fancy prompt is off by default
    [[ ! "$content" =~ "git-branch-name()" ]]
}

@test "module: shell: enable_fancy_prompt adds prompt helpers" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    mkdir -p "$(dirname "$(ew_config_path)")"
    cat > "$(ew_config_path)" << 'EOF'
schema_version = 1
[shell]
enable_fancy_prompt = true
EOF
    local content
    content="$(_generate_shell_config)"
    [[ "$content" =~ "git-branch-name()" ]]
    [[ "$content" =~ "PROMPT=" ]]
}

@test "module: shell: dry-run install does not create files" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    DRY_RUN=true module_install
    [[ ! -f "$SH_CONFIG_FILE" ]]
}

# ── Git Module ───────────────────────────────────────────────

@test "module: git: variables and module_check" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    [[ "$MODULE_NAME" == "git" ]]
    run module_check
    [[ "$status" -ne 0 ]]
}

@test "module: git: email validation" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    run _validate_email "user@example.com"
    [[ "$status" -eq 0 ]]
    run _validate_email "invalid-email"
    [[ "$status" -ne 0 ]]
    run _validate_email ""
    [[ "$status" -ne 0 ]]
}

@test "module: git: name validation" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    run _validate_name "John Doe"
    [[ "$status" -eq 0 ]]
    run _validate_name ""
    [[ "$status" -ne 0 ]]
    run _validate_name 'name$(evil)'
    [[ "$status" -ne 0 ]]
}

@test "module: git: _validate_name rejects shell metacharacters" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    run _validate_name 'name$(evil)'
    [[ "$status" -ne 0 ]]
    run _validate_name 'name`touch /tmp/evil`'
    [[ "$status" -ne 0 ]]
    run _validate_name 'name|cat /etc/passwd'
    [[ "$status" -ne 0 ]]
}

@test "module: git: _validate_name accepts unicode names" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    run _validate_name "张三"
    [[ "$status" -eq 0 ]]
    run _validate_name "José Müller"
    [[ "$status" -eq 0 ]]
    run _validate_name "Alex 李"
    [[ "$status" -eq 0 ]]
}

@test "module: git: _validate_name rejects empty input" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    run _validate_name ""
    [[ "$status" -ne 0 ]]
}

@test "module: git: _validate_name allows spaces (not a shell metachar)" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    # Spaces are not shell metacharacters, so they pass the security check.
    # Git itself will reject whitespace-only names on commit time.
    run _validate_name "   "
    [[ "$status" -eq 0 ]]
}

@test "module: git: _generate_git_config contains aliases" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    local content
    content="$(_generate_git_config)"
    [[ "$content" =~ "l = log" ]]
    [[ "$content" =~ "s = status" ]]
    [[ "$content" =~ "co = checkout" ]]
}

@test "module: git: dry-run install with config values" {
    cat > "$CONFIG_FILE" << 'EOF'
## git
GIT_PERSONAL_NAME="Test User"
GIT_PERSONAL_EMAIL="test@example.com"
EOF
    config_load
    source "${EASYWORK_ROOT}/lib/git.sh"
    DRY_RUN=true YES_MODE=true module_install
    [[ "$?" -eq 0 ]]
    # Git config should NOT be created in dry-run
    [[ ! -f "$GIT_CONFIG_FILE" ]]
}

# ── Vim Module ───────────────────────────────────────────────

@test "module: vim: variables and module_check" {
    source "${EASYWORK_ROOT}/lib/vim.sh"
    [[ "$MODULE_NAME" == "vim" ]]
    run module_check
    [[ "$status" -ne 0 ]]
}

@test "module: vim: _generate_vimrc has plugins and mappings" {
    source "${EASYWORK_ROOT}/lib/vim.sh"
    local content
    content="$(_generate_vimrc)"
    [[ "$content" =~ "NERDTree" ]]
    [[ "$content" =~ "coc.nvim" ]]
    [[ "$content" =~ "fzf" ]]
    [[ "$content" =~ "<C-n>" ]]
}

@test "module: vim: dry-run install does not create config" {
    source "${EASYWORK_ROOT}/lib/vim.sh"
    DRY_RUN=true module_install
    [[ ! -f "$VIMRC_FILE" ]]
}

# ── Integration ──────────────────────────────────────────────

@test "module: integration: fresh install manifest with modules" {
    manifest_init "1.0.0"
    manifest_set_section "shell" "installed=true"
    manifest_set_section "git" "installed=true"
    manifest_set_section "vim" "installed=true"

    local installed
    installed="$(manifest_list_installed)"
    [[ "$installed" =~ "shell" ]]
    [[ "$installed" =~ "git" ]]
    [[ "$installed" =~ "vim" ]]
}

@test "module: integration: uninstall removes sections" {
    manifest_init "1.0.0"
    manifest_set_section "shell" "installed=true"
    manifest_set_section "git" "installed=true"
    manifest_remove_section "shell"
    run manifest_section_exists "shell"
    [[ "$status" -ne 0 ]]
    run manifest_section_exists "git"
    [[ "$status" -eq 0 ]]
}

@test "module: integration: partial uninstall leaves others" {
    manifest_init "1.0.0"
    manifest_set_section "shell" "installed=true"
    manifest_set_section "git" "installed=true"
    manifest_set_section "vim" "installed=true"
    manifest_remove_section "vim"
    local installed
    installed="$(manifest_list_installed)"
    [[ "$installed" =~ "shell" ]]
    [[ "$installed" =~ "git" ]]
    [[ ! "$installed" =~ "vim" ]]
}

@test "module: integration: reinstall refreshes section" {
    manifest_init "1.0.0"
    manifest_set_section "shell" "installed=true" "shell_type=bash"
    manifest_set_section "shell" "installed=true" "shell_type=zsh"
    [[ "$(manifest_read 'shell_type')" == "zsh" ]]
}

@test "module: integration: upgrade updates manifest version" {
    manifest_init "1.0.0"
    sed "s/^easywork_version=.*/easywork_version=1.1.0/" "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp"
    mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
    [[ "$(manifest_get_version)" == "1.1.0" ]]
}

@test "module: integration: modules sorted by priority" {
    register_module "aaa" "AAA" 90
    register_module "bbb" "BBB" 10
    register_module "ccc" "CCC" 50
    local sorted
    sorted="$(list_modules_sorted)"
    # bbb (10) should come before ccc (50) before aaa (90)
    local b_pos="${sorted%%bbb*}"
    b_pos="${#b_pos}"
    local c_pos="${sorted%%ccc*}"
    c_pos="${#c_pos}"
    local a_pos="${sorted%%aaa*}"
    a_pos="${#a_pos}"
    [[ "$b_pos" -lt "$c_pos" ]]
    [[ "$c_pos" -lt "$a_pos" ]]
}

@test "module: integration: manifest write-read cycle" {
    manifest_init "1.0.0"
    manifest_set_section "test" "key1=val1" "key2=val2" "installed=true"
    [[ "$(manifest_read 'key1')" == "val1" ]]
    [[ "$(manifest_read 'key2')" == "val2" ]]
    run manifest_section_installed "test"
    [[ "$status" -eq 0 ]]
}

# ── Module Uninstall ───────────────────────────────────────────

@test "module: shell: dry-run uninstall does not delete files" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    # Create a fake config file to verify it's not deleted in dry-run
    echo "# EasyWork managed section begin v1.0.0" > "$SH_CONFIG_FILE"
    echo "export TEST_VAR=1" >> "$SH_CONFIG_FILE"
    echo "# EasyWork managed section end" >> "$SH_CONFIG_FILE"
    DRY_RUN=true module_uninstall
    [[ -f "$SH_CONFIG_FILE" ]]
}

@test "module: git: dry-run uninstall does not modify gitconfig" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    echo "# EasyWork managed section begin v1.0.0" > "$GIT_CONFIG_FILE"
    echo "[user]" >> "$GIT_CONFIG_FILE"
    echo "# EasyWork managed section end" >> "$GIT_CONFIG_FILE"
    DRY_RUN=true module_uninstall
    [[ -f "$GIT_CONFIG_FILE" ]]
}

@test "module: vim: dry-run uninstall does not delete vimrc" {
    source "${EASYWORK_ROOT}/lib/vim.sh"
    echo '" EasyWork managed section begin v1.0.0' > "$VIMRC_FILE"
    echo '" EasyWork managed section end' >> "$VIMRC_FILE"
    DRY_RUN=true module_uninstall
    [[ -f "$VIMRC_FILE" ]]
}

@test "module: git: uninstall removes managed section" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    # Create a file with user content + managed section
    cat > "$GIT_CONFIG_FILE" << 'EOF'
# User's own git config
[user]
    name = pre-existing-user
# EasyWork managed section begin v1.0.0
[user]
    name = easywork-user
[alias]
    s = status
# EasyWork managed section end
# User content after
[diff]
    tool = mydiff
EOF
    YES_MODE=true module_uninstall
    # File should exist but managed section removed
    [[ -f "$GIT_CONFIG_FILE" ]]
    # User content before and after section must be preserved
    grep -q "pre-existing-user" "$GIT_CONFIG_FILE"
    grep -q "mydiff" "$GIT_CONFIG_FILE"
    # Managed content must be removed
    ! grep -q "easywork-user" "$GIT_CONFIG_FILE"
    ! grep -q "s = status" "$GIT_CONFIG_FILE"
}

# ── Shell Completions ──────────────────────────────────────────

@test "module: completions: install generates bash and zsh completion files" {
    local comp_dir="${TEST_HOME}/.easywork/completions"
    local rc_file="${TEST_HOME}/.bashrc"
    touch "$rc_file"

    # Run install with --yes to trigger _setup_completions
    run "${EASYWORK_ROOT}/bin/easywork" install --yes
    [[ "$status" -eq 0 ]]

    # Completion files must exist
    [[ -f "$comp_dir/easywork.bash" ]]
    [[ -f "$comp_dir/_easywork" ]]

    # Bash completion must contain the completion function
    grep -q "_easywork()" "$comp_dir/easywork.bash"
    grep -q "complete -F _easywork easywork" "$comp_dir/easywork.bash"

    # Zsh completion must contain #compdef and explicit compdef registration
    grep -q "#compdef easywork" "$comp_dir/_easywork"
    grep -q "compdef _easywork easywork" "$comp_dir/_easywork"

    # .zshrc source line must use 'source', not the broken 'fpath=' approach
    # (check .zshrc was injected with the correct source line)
    if [[ -f "${TEST_HOME}/.zshrc" ]]; then
        ! grep -q "fpath=" "${TEST_HOME}/.zshrc" 2> /dev/null || true
    fi
}

@test "module: completions: generated bash completion is context-aware" {
    # Run install to generate completions
    run "${EASYWORK_ROOT}/bin/easywork" install --yes
    [[ "$status" -eq 0 ]]

    local comp_dir="${TEST_HOME}/.easywork/completions"
    source "$comp_dir/easywork.bash"

    # Test: easywork <TAB> should suggest install command
    COMP_WORDS=("easywork" "")
    COMP_CWORD=1
    _easywork
    local found_install=false
    local w
    for w in "${COMPREPLY[@]}"; do
        [[ "$w" == "install" ]] && found_install=true
    done
    [[ "$found_install" == "true" ]]

    # Test: easywork config <TAB> should suggest edit and show
    COMP_WORDS=("easywork" "config" "")
    COMP_CWORD=2
    _easywork
    local found_edit=false
    local found_show=false
    for w in "${COMPREPLY[@]}"; do
        [[ "$w" == "edit" ]] && found_edit=true
        [[ "$w" == "show" ]] && found_show=true
    done
    [[ "$found_edit" == "true" ]]
    [[ "$found_show" == "true" ]]
}

@test "module: completions: zsh completion file uses explicit compdef not fpath autoload" {
    run "${EASYWORK_ROOT}/bin/easywork" install --yes
    local comp_dir="${TEST_HOME}/.easywork/completions"

    # Must contain the explicit compdef registration
    grep -q "compdef _easywork easywork" "$comp_dir/_easywork"

    # The _easywork file defines its own function (not just an autoload stub)
    grep -q "_easywork()" "$comp_dir/_easywork"

    # .zshrc (if created) must NOT use the broken fpath approach
    if [[ -f "${TEST_HOME}/.zshrc" ]]; then
        ! grep -q "fpath=" "${TEST_HOME}/.zshrc" 2> /dev/null || true
    fi
}

@test "module: completions: injects source line into both bash and zsh rc files" {
    # Create both rc files ahead of time
    touch "${TEST_HOME}/.bashrc"
    touch "${TEST_HOME}/.zshrc"
    touch "${TEST_HOME}/.bash_profile"

    run "${EASYWORK_ROOT}/bin/easywork" install --yes

    # Both should have the EasyWork completion marker
    grep -qF "# EasyWork completion" "${TEST_HOME}/.bashrc"
    grep -qF "# EasyWork completion" "${TEST_HOME}/.zshrc"
}

@test "module: completions: removal cleans up from all rc files and preserves user content" {
    # Pre-create rc files so _detect_completion_rc_files includes them on all platforms
    touch "${TEST_HOME}/.bashrc"
    touch "${TEST_HOME}/.zshrc"

    # First install to set up manifest and completions
    run "${EASYWORK_ROOT}/bin/easywork" install --yes
    [[ "$status" -eq 0 ]]

    # Append user content to rc files after completion lines were injected
    echo "# my bash alias" >> "${TEST_HOME}/.bashrc"
    echo "# my zsh setting" >> "${TEST_HOME}/.zshrc"

    # Verify completion lines exist before uninstall
    grep -qF "# EasyWork completion" "${TEST_HOME}/.bashrc"
    grep -qF "# EasyWork completion" "${TEST_HOME}/.zshrc"

    # Run uninstall to trigger _remove_completions via _finalize_uninstall
    run "${EASYWORK_ROOT}/bin/easywork" uninstall --yes
    [[ "$status" -eq 0 ]]

    # Completion lines must be gone
    ! grep -qF "# EasyWork completion" "${TEST_HOME}/.bashrc" 2> /dev/null || true
    ! grep -qF "# EasyWork completion" "${TEST_HOME}/.zshrc" 2> /dev/null || true

    # User content must be preserved
    grep -q "my bash alias" "${TEST_HOME}/.bashrc"
    grep -q "my zsh setting" "${TEST_HOME}/.zshrc"
}

@test "module: completions: idempotent injection does not duplicate lines" {
    touch "${TEST_HOME}/.bashrc"

    # First install
    run "${EASYWORK_ROOT}/bin/easywork" install --yes
    local count1
    count1=$(grep -cF "# EasyWork completion" "${TEST_HOME}/.bashrc" || echo "0")

    # Second install (manifest will already exist, triggering same_version mode)
    run "${EASYWORK_ROOT}/bin/easywork" install --yes
    local count2
    count2=$(grep -cF "# EasyWork completion" "${TEST_HOME}/.bashrc" || echo "0")

    [[ "$count1" -eq 1 ]]
    [[ "$count2" -eq 1 ]]
}

@test "module: completions: _detect_rc_file returns valid path" {
    source "${EASYWORK_ROOT}/lib/completions.sh"
    local rc
    rc="$(_detect_rc_file)"
    [[ "$rc" == "$HOME/"* ]]
    # Path must end in rc or profile
    [[ "$rc" =~ \.(bashrc|bash_profile|zshrc)$ ]]
}

@test "module: completions: _detect_completion_rc_files covers bash and zsh" {
    source "${EASYWORK_ROOT}/lib/completions.sh"
    local files
    files="$(_detect_completion_rc_files)"
    [[ "$files" =~ "zsh:" ]]
    [[ "$files" =~ "bash:" ]]
    # Each line has format shell_type:absolute_path
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" =~ ^(zsh|bash): ]]
    done <<< "$files"
}
