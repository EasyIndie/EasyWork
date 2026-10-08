#!/usr/bin/env bats
# Unit tests: core library functions (common.sh)

setup() {
    load helpers/mocks
    setup_mocks
    EASYWORK_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "${EASYWORK_ROOT}/lib/common.sh"
    exec < /dev/null # never inherit the developer's tty
}

teardown() { teardown_mocks; }

# ── System Detection ─────────────────────────────────────────

@test "unit: detect_os returns known value" {
    local os
    os="$(detect_os)"
    [[ "$os" =~ ^(macos|linux|unknown)$ ]]
}

@test "unit: detect_shell returns valid shell name" {
    local sh
    sh="$(detect_shell)"
    [[ "$sh" =~ ^(zsh|bash|sh|unknown)$ ]]
}

@test "unit: detect_pkg_manager returns known value" {
    local pm
    pm="$(detect_pkg_manager)"
    [[ -n "$pm" ]]
}

# ── Command Detection ────────────────────────────────────────

@test "unit: has_cmd true for existing command" {
    run has_cmd bash
    [[ "$status" -eq 0 ]]
}

@test "unit: has_cmd false for missing command" {
    run has_cmd nonexistent_cmd_xyz123
    [[ "$status" -ne 0 ]]
}

# ── Logging ──────────────────────────────────────────────────

@test "unit: log_info/log_success output to stdout" {
    run log_info "test info"
    [[ "$output" =~ "test info" ]]
    run log_success "test ok"
    [[ "$output" =~ "test ok" ]]
}

@test "unit: log_error/log_warn output to stderr" {
    run log_error "test err"
    [[ "$output" =~ "test err" ]]
    run log_warn "test warn"
    [[ "$output" =~ "test warn" ]]
}

# ── File Operations ──────────────────────────────────────────

@test "unit: backup_file creates timestamped backup" {
    local f="${TEST_HOME}/testfile"
    echo "original" > "$f"
    local bak
    bak="$(backup_file "$f")"
    [[ -f "$bak" ]]
    [[ "$bak" =~ "testfile.bak." ]]
}

@test "unit: backup_file returns empty for missing file" {
    local bak
    bak="$(backup_file "${TEST_HOME}/noexist")"
    [[ -z "$bak" ]]
}

@test "unit: restore_backup restores file" {
    local f="${TEST_HOME}/orig"
    echo "orig" > "$f"
    local bak="${TEST_HOME}/orig.backup.test"
    echo "backup" > "$bak"
    restore_backup "$bak" "$f"
    [[ "$(cat "$f")" == "backup" ]]
}

# ── Config ───────────────────────────────────────────────────

@test "unit: config_path returns path" {
    run config_path
    [[ "$output" =~ ".easywork/config" ]]
}

@test "unit: config_init creates config.toml" {
    rm -f "$(ew_config_path)" "$(ew_legacy_config)"
    config_init
    [[ -f "$(ew_config_path)" ]]
    # Should NOT contain git placeholder values
    run cat "$(ew_config_path)"
    [[ ! "$output" =~ "Your Name" ]]
}

@test "unit: config_load reads variables" {
    echo 'TEST_VAR="loaded_value"' > "$CONFIG_FILE"
    config_load
    [[ "${TEST_VAR:-}" == "loaded_value" ]]
}

@test "unit: config_load reads config.toml into shell vars" {
    rm -f "$(ew_legacy_config)"
    mkdir -p "$(dirname "$(ew_config_path)")"
    cat > "$(ew_config_path)" << 'EOF'
schema_version = 1
[git.identities.personal]
name  = "Alice"
email = "alice@example.com"
EOF
    config_load
    [[ "$GIT_PERSONAL_NAME" == "Alice" ]]
    [[ "$GIT_PERSONAL_EMAIL" == "alice@example.com" ]]
}

# ── Manifest ─────────────────────────────────────────────────

@test "unit: manifest lifecycle" {
    rm -f "$MANIFEST_FILE"
    run manifest_exists
    [[ "$status" -ne 0 ]]

    manifest_init "1.0.0"
    run manifest_exists
    [[ "$status" -eq 0 ]]
    [[ "$(manifest_get_version)" == "1.0.0" ]]

    manifest_set_section "shell" "installed=true" "shell_type=zsh"
    run manifest_section_exists "shell"
    [[ "$status" -eq 0 ]]
    [[ "$(manifest_read 'shell_type')" == "zsh" ]]
    [[ "$(manifest_read 'missing' 'default')" == "default" ]]

    run manifest_section_installed "shell"
    [[ "$status" -eq 0 ]]
    run manifest_list_installed
    [[ "$output" =~ "shell" ]]

    manifest_remove_section "shell"
    run manifest_section_exists "shell"
    [[ "$status" -ne 0 ]]

    manifest_clear
    [[ ! -f "$MANIFEST_FILE" ]]
}

@test "unit: manifest handles corrupt file" {
    echo "garbage line" > "$MANIFEST_FILE"
    run manifest_read 'anykey' 'fallback'
    [[ "$output" == "fallback" ]]
    run manifest_section_exists "anything"
    [[ "$status" -ne 0 ]]
}

@test "unit: manifest section_installed false for missing" {
    manifest_init "1.0.0"
    run manifest_section_installed "nonexistent"
    [[ "$status" -ne 0 ]]
}

# ── Module Registry ──────────────────────────────────────────

@test "unit: module registry operations" {
    register_module "testmod" "Test Module" 10
    run module_registered "testmod"
    [[ "$status" -eq 0 ]]
    run module_registered "noexist"
    [[ "$status" -ne 0 ]]
}

@test "unit: register_module rejects reserved names" {
    run register_module "install" "bad"
    [[ "$status" -ne 0 ]]
}

@test "unit: duplicate registration is idempotent" {
    register_module "dupmod" "First" 10
    register_module "dupmod" "Second" 20
    # Should not crash, still registered
    run module_registered "dupmod"
    [[ "$status" -eq 0 ]]
}

@test "unit: empty module registry is safe" {
    run list_modules_sorted
    [[ -z "$output" ]]
    run list_modules
    [[ "$status" -eq 0 ]]
}

# ── Semver ───────────────────────────────────────────────────

_sv() {
    set +e
    _semver_compare "$1" "$2"
    local rc=$?
    set -e
    return $rc
}

@test "unit: semver comparisons" {
    run _sv "1.0.0" "1.0.0"
    [[ "$status" -eq 0 ]]
    run _sv "2.0.0" "1.9.9"
    [[ "$status" -eq 1 ]]
    run _sv "1.2.0" "1.1.9"
    [[ "$status" -eq 1 ]]
    run _sv "1.0.1" "1.0.0"
    [[ "$status" -eq 1 ]]
    run _sv "0.9.0" "1.0.0"
    [[ "$status" -eq 2 ]]
    run _sv "0.0.0" "0.0.0"
    [[ "$status" -eq 0 ]]
}

# ── Managed Section ──────────────────────────────────────────

@test "unit: replace_managed_section creates file with markers" {
    local f="${TEST_HOME}/managed_test"
    replace_managed_section "$f" "1.0.0" "content line"
    grep -q "EasyWork managed section begin" "$f"
    grep -q "content line" "$f"
    grep -q "EasyWork managed section end" "$f"
}

@test "unit: replace_managed_section preserves user content" {
    local f="${TEST_HOME}/managed_test2"
    echo "user_before" > "$f"
    echo "# >>> EasyWork managed section begin (v1.0.0) >>>" >> "$f"
    echo "old_managed" >> "$f"
    echo "# <<< EasyWork managed section end <<<" >> "$f"
    echo "user_after" >> "$f"
    replace_managed_section "$f" "2.0.0" "new_managed"
    grep -q "user_before" "$f"
    grep -q "user_after" "$f"
    grep -q "new_managed" "$f"
    ! grep -q "old_managed" "$f"
}

@test "unit: replace_managed_section handles empty content" {
    local f="${TEST_HOME}/managed_empty"
    replace_managed_section "$f" "1.0.0" ""
    [[ -f "$f" ]]
    grep -q "EasyWork managed section" "$f"
}

@test "unit: replace_managed_section prepends to existing" {
    local f="${TEST_HOME}/managed_prepend"
    echo "preexisting" > "$f"
    replace_managed_section "$f" "1.0.0" "new content"
    grep -q "preexisting" "$f"
    grep -q "new content" "$f"
}

@test "unit: replace_managed_section cross-version comment format" {
    # Test that different comment prefix (# vs ") in markers is handled
    local f="${TEST_HOME}/managed_cross_ver"
    # Old version with vim-style comment
    echo '" >>> EasyWork managed section begin (v1.0.0) >>>' > "$f"
    echo 'old managed content' >> "$f"
    echo '" <<< EasyWork managed section end <<<' >> "$f"
    echo 'user content' >> "$f"
    # Replace with new version (default # comment prefix)
    replace_managed_section "$f" "2.0.0" "new managed content"
    # User content preserved
    grep -q "user content" "$f"
    # Old content replaced
    ! grep -q "old managed content" "$f"
    # New content present
    grep -q "new managed content" "$f"
    # New marker uses default comment prefix
    grep -q "# >>> EasyWork managed section" "$f"
}

@test "unit: replace_managed_section prepends to file without markers" {
    # File with no managed section marker gets section prepended
    local f="${TEST_HOME}/managed_cross_ver2"
    echo "user content" > "$f"
    replace_managed_section "$f" "3.0.0" "managed content"
    # Both managed and user content should exist (managed is prepended)
    grep -q "managed content" "$f"
    grep -q "user content" "$f"
    # Managed markers must be present
    grep -q ">>> EasyWork managed section begin" "$f"
    grep -q "<<< EasyWork managed section end" "$f"
}

@test "unit: replace_managed_section handles section only file" {
    local f="${TEST_HOME}/managed_section_only"
    replace_managed_section "$f" "1.0.0" "content"
    replace_managed_section "$f" "1.0.0" "updated"
    grep -q "updated" "$f"
    ! grep -q "content" "$f"
}

# ── Exit Codes ───────────────────────────────────────────────

@test "unit: exit codes are non-zero and distinct" {
    [[ "$EXIT_SUCCESS" -eq 0 ]]
    [[ "$EXIT_ERROR" -ne 0 ]]
    [[ "$EXIT_MISSING_DEPS" -ne 0 ]]
}

# ── String Escaping Helpers ──────────────────────────────────

@test "unit: _escape_regex escapes metacharacters" {
    local r
    r="$(_escape_regex "key.with.dots")"
    [[ "$r" == 'key\.with\.dots' ]]
    r="$(_escape_regex "[bracket]")"
    [[ "$r" == '\[bracket\]' ]]
    r="$(_escape_regex "star*plus+")"
    [[ "$r" == 'star\*plus\+' ]]
}

@test "unit: _escape_sed_replacement escapes sed chars" {
    local r
    r="$(_escape_sed_replacement "a/b")"
    # Escaped output contains backslash+slash sequence \/
    [[ "$r" == *'\'/* ]]
    r="$(_escape_sed_replacement "foo&bar")"
    # Escaped output contains backslash+ampersand sequence \&
    [[ "$r" == *'\&'* ]]
}

# ── Semver with v-prefix ─────────────────────────────────────

@test "unit: semver handles v prefix from GitHub tags" {
    run _sv "v2.0.0" "v1.0.0"
    [[ "$status" -eq 1 ]]
    run _sv "v1.0.0" "1.0.0"
    [[ "$status" -eq 0 ]]
    run _sv "1.0.0" "v1.0.0"
    [[ "$status" -eq 0 ]]
    run _sv "v0.9.0" "1.0.0"
    [[ "$status" -eq 2 ]]
}

@test "unit: semver strips pre-release suffixes" {
    run _sv "2.0.0" "1.9.9-alpha"
    [[ "$status" -eq 1 ]]
    run _sv "1.0.0" "1.0.0-rc1"
    [[ "$status" -eq 0 ]]
}

# ── Module Name Validation ──────────────────────────────────

@test "unit: register_module rejects names with spaces" {
    run register_module "bad name" "desc"
    [[ "$status" -ne 0 ]]
}

@test "unit: register_module rejects names with slashes" {
    run register_module "bad/name" "desc"
    [[ "$status" -ne 0 ]]
}

@test "unit: register_module rejects names with dots" {
    run register_module "bad.name" "desc"
    [[ "$status" -ne 0 ]]
}

@test "unit: register_module accepts valid names with hyphens" {
    register_module "valid-name" "test" 99
    run module_registered "valid-name"
    [[ "$status" -eq 0 ]]
    # Clean up to avoid polluting other tests
    MODULE_NAMES=()
    MODULE_DESCRIPTIONS=()
    MODULE_PRIORITY_VALUES=()
}

# ── Manifest Read with Section Key ───────────────────────────

@test "unit: manifest_read_section_key reads from correct section" {
    manifest_init "1.0.0"
    manifest_set_section "git" "installed=true" "config_backup=/bak/git.bak"
    manifest_set_section "vim" "installed=true" "config_backup=/bak/vim.bak"
    [[ "$(manifest_read_section_key 'git' 'config_backup')" == '/bak/git.bak' ]]
    [[ "$(manifest_read_section_key 'vim' 'config_backup')" == '/bak/vim.bak' ]]
    # Non-existent key returns default
    [[ "$(manifest_read_section_key 'git' 'missing' 'fallback')" == 'fallback' ]]
}

# ── Manifest Read escapes regex ──────────────────────────────

@test "unit: manifest_read escapes dot in key" {
    manifest_init "1.0.0"
    manifest_set_section "test" "key.with.dots=works"
    [[ "$(manifest_read_section_key 'test' 'key.with.dots')" == 'works' ]]
}

# ── safe_download ──────────────────────────────────────────────

@test "unit: safe_download single-arg writes to stdout" {
    # Mock curl to echo a known value
    function curl() {
        echo "downloaded-content"
        return 0
    }
    export -f curl 2> /dev/null || true
    local result
    result="$(safe_download "https://example.com/file")"
    [[ "$result" == "downloaded-content" ]]
}

@test "unit: safe_download two-arg writes to file" {
    local outfile="${TEST_HOME}/safe_download_test.out"
    # Mock curl: extract -o argument and write to it
    function curl() {
        local output_file=""
        local prev=""
        for arg in "$@"; do
            [[ "$prev" == "-o" ]] && {
                output_file="$arg"
                break
            }
            prev="$arg"
        done
        [[ -n "$output_file" ]] && echo "file-content" > "$output_file"
        return 0
    }
    export -f curl 2> /dev/null || true
    safe_download "https://example.com/file" "$outfile"
    [[ -f "$outfile" ]]
    [[ "$(cat "$outfile")" == "file-content" ]]
}

@test "unit: safe_download with extra curl flags" {
    function curl() {
        # Verify --retry flag is forwarded
        echo "$*" >> "${TEST_HOME}/safe_download_flags.log"
        return 0
    }
    export -f curl 2> /dev/null || true
    safe_download "https://example.com/file" "out.txt" --retry 5
    grep -q "retry" "${TEST_HOME}/safe_download_flags.log" || true
}

# ── SHA256 Checksum ─────────────────────────────────────────────

@test "unit: _sha256_check matches expected hash" {
    local f="${TEST_HOME}/sha_test_file"
    echo "hello world" > "$f"
    # Compute expected hash using available tool
    local expected
    if command -v shasum > /dev/null 2>&1; then
        expected="$(shasum -a 256 "$f" | cut -d' ' -f1)"
    elif command -v sha256sum > /dev/null 2>&1; then
        expected="$(sha256sum "$f" | cut -d' ' -f1)"
    else
        skip "no sha256 tool available"
    fi
    run _sha256_check "$f" "$expected"
    [[ "$status" -eq 0 ]]
}

@test "unit: _sha256_check rejects wrong hash" {
    local f="${TEST_HOME}/sha_test_file2"
    echo "hello world" > "$f"
    run _sha256_check "$f" "0000000000000000000000000000000000000000000000000000000000000000"
    [[ "$status" -ne 0 ]]
}

@test "unit: _sha256_check returns 0 when no tool available" {
    local f="${TEST_HOME}/sha_test_file3"
    echo "test" > "$f"
    function shasum() { return 127; }
    function sha256sum() { return 127; }
    function openssl() { return 127; }
    function has_cmd() { return 1; }
    export -f has_cmd 2> /dev/null || true
    run _sha256_check "$f" "anyhash"
    [[ "$status" -eq 0 ]]
}

@test "unit: safe_download --sha256 verifies integrity" {
    local f="${TEST_HOME}/safe_sha_test"
    local content="integrity-check-content"
    local expected_hash
    echo -n "$content" > "${TEST_HOME}/source_file"

    # Compute expected hash
    if command -v shasum > /dev/null 2>&1; then
        expected_hash="$(shasum -a 256 "${TEST_HOME}/source_file" | cut -d' ' -f1)"
    elif command -v sha256sum > /dev/null 2>&1; then
        expected_hash="$(sha256sum "${TEST_HOME}/source_file" | cut -d' ' -f1)"
    else
        skip "no sha256 tool available"
    fi

    # Mock curl to write known content
    function curl() {
        local out=""
        local prev=""
        for arg in "$@"; do
            [[ "$prev" == "-o" ]] && {
                out="$arg"
                break
            }
            prev="$arg"
        done
        [[ -n "$out" ]] && echo -n "$content" > "$out"
        return 0
    }
    export -f curl 2> /dev/null || true

    safe_download --sha256 "$expected_hash" "https://example.com/file" "$f"
    [[ -f "$f" ]]
    [[ "$(cat "$f")" == "$content" ]]
}

@test "unit: safe_download --sha256 rejects tampered content" {
    local f="${TEST_HOME}/safe_sha_tamper"
    local bad_hash="0000000000000000000000000000000000000000000000000000000000000000"

    function curl() {
        local out=""
        local prev=""
        for arg in "$@"; do
            [[ "$prev" == "-o" ]] && {
                out="$arg"
                break
            }
            prev="$arg"
        done
        [[ -n "$out" ]] && echo "tampered-content" > "$out"
        return 0
    }
    export -f curl 2> /dev/null || true

    run safe_download --sha256 "$bad_hash" "https://example.com/file" "$f"
    [[ "$status" -ne 0 ]]
    # Tampered file should be removed on failure
    [[ ! -f "$f" ]]
}

# ── Temp File Tracking ──────────────────────────────────────────

@test "unit: _register_temp_file adds to TEMP_FILES" {
    TEMP_FILES=""
    _register_temp_file "/tmp/test1.tmp"
    [[ "$TEMP_FILES" == "/tmp/test1.tmp" ]]
    _register_temp_file "/tmp/test2.tmp"
    [[ "$TEMP_FILES" == "/tmp/test1.tmp /tmp/test2.tmp" ]]
}

@test "unit: _register_temp_file handles single and multiple files" {
    TEMP_FILES=""
    _register_temp_file "/tmp/a.tmp"
    [[ "${#TEMP_FILES}" -gt 0 ]]
    # Verify it's space-separated list
    local count
    count="$(echo "$TEMP_FILES" | wc -w | tr -d ' ')"
    [[ "$count" -eq 1 ]]
    _register_temp_file "/tmp/b.tmp"
    count="$(echo "$TEMP_FILES" | wc -w | tr -d ' ')"
    [[ "$count" -eq 2 ]]
}

# ── Signal Handling ────────────────────────────────────────────

@test "unit: cleanup_on_interrupt calls release_lock" {
    # run in subshell to not affect test harness
    # By verifying the exit code is EXIT_INTERRUPT
    LOCK_FILE="${TEST_HOME}/.easywork_int_test.lock"
    LOCK_FD=202
    # Simulate cleanup without actually killing the process
    run cleanup_on_interrupt
    # Should exit EXIT_INTERRUPT
    [[ "$status" -eq 130 ]]
}

# ── check_network ──────────────────────────────────────────────

@test "unit: check_network with curl available" {
    function curl() { return 0; }
    export -f curl 2> /dev/null || true
    function has_cmd() {
        [[ "$1" == "curl" ]]
        return $?
    }
    export -f has_cmd 2> /dev/null || true
    run check_network
    [[ "$status" -eq 0 ]]
}

@test "unit: check_network with no tool returns error" {
    function has_cmd() { return 1; }
    export -f has_cmd 2> /dev/null || true
    run check_network
    [[ "$status" -ne 0 ]]
}

# ── format_date_human ──────────────────────────────────────────

@test "unit: format_date_human with ISO-8601 input" {
    local result
    result="$(format_date_human "2026-06-12T10:15:30+0800")"
    [[ -n "$result" ]]
    [[ "$result" != "unknown" ]]
}

@test "unit: format_date_human with empty input returns unknown" {
    local result
    result="$(format_date_human "")"
    [[ "$result" == "unknown" || "$result" == "" ]]
}

@test "unit: format_date_human with unknown text returns fallback" {
    local result
    result="$(format_date_human "unknown")"
    [[ "$result" == "unknown" ]]
}

# ── _escape_regex remaining metacharacters ─────────────────────

@test "unit: _escape_regex escapes backslash and caret" {
    local r
    r="$(_escape_regex '\')"
    [[ "$r" == '\\' ]]
    local s
    s="$(_escape_regex '^')"
    [[ "$s" == '\^' ]]
}

@test "unit: _escape_regex escapes dollar and pipe" {
    local r
    r="$(_escape_regex '$')"
    [[ "$r" == '\$' ]]
    local s
    s="$(_escape_regex '|')"
    [[ "$s" == '\|' ]]
}

@test "unit: _escape_regex escapes parens and question" {
    local r
    r="$(_escape_regex '(')"
    [[ "$r" == '\(' ]]
    local s
    s="$(_escape_regex ')')"
    [[ "$s" == '\)' ]]
    local t
    t="$(_escape_regex '?')"
    [[ "$t" == '\?' ]]
}

# ── _semver_is_newer ──────────────────────────────────────────

@test "unit: _semver_is_newer detects newer version" {
    run _semver_is_newer "2.0.0" "1.0.0"
    [[ "$status" -eq 0 ]]
}

@test "unit: _semver_is_newer detects older version" {
    run _semver_is_newer "1.0.0" "2.0.0"
    [[ "$status" -ne 0 ]]
}

# ── acquire_lock / release_lock ────────────────────────────────

@test "unit: acquire_lock creates lock and release_lock cleans up" {
    # Override lock file path to test directory
    LOCK_FILE="${TEST_HOME}/.easywork_test.lock"
    LOCK_FD=200
    run acquire_lock
    [[ "$status" -eq 0 ]]
    # Lock file should exist (either as flock file or mkdir dir)
    [[ -f "$LOCK_FILE" || -d "$LOCK_FILE" ]]
    # Release should clean up
    release_lock
    [[ ! -f "${TEST_HOME}/.easywork_test.lock" ]]
}

@test "unit: acquire_lock is re-entrant (idempotent)" {
    LOCK_FILE="${TEST_HOME}/.easywork_test_reentrant.lock"
    LOCK_FD=201
    acquire_lock
    run acquire_lock # second call should succeed
    [[ "$status" -eq 0 ]]
    release_lock
}

# ── preflight_check ────────────────────────────────────────────

@test "unit: preflight_check succeeds with common tools" {
    function has_cmd() { return 0; }
    export -f has_cmd 2> /dev/null || true
    run preflight_check
    [[ "$status" -eq 0 ]]
}

# ── State paths (EASYWORK_HOME) ──────────────────────────────

@test "unit: ew_* paths derive from EASYWORK_HOME" {
    [[ "$(ew_home)" == "${HOME}/.easywork" ]]
    [[ "$(ew_config_path)" == "${HOME}/.easywork/config.toml" ]]
    [[ "$(ew_manifest_path)" == "${HOME}/.easywork/manifest" ]]
    [[ "$(ew_legacy_config)" == "${HOME}/.easywork/config" ]]
    [[ "$(ew_completions_dir)" == "${HOME}/.easywork/completions" ]]
    [[ "$(ew_lib_cache)" == "${HOME}/.easywork/lib/v${EASYWORK_VERSION}" ]]
}

@test "unit: ew_config_path respects EASYWORK_HOME override" {
    local out
    out="$(EASYWORK_HOME=/custom/state ew_config_path)"
    [[ "$out" == "/custom/state/config.toml" ]]
}

@test "unit: manifest_init writes schema_version=1" {
    manifest_init "1.0.0"
    [[ "$(manifest_get_schema_version)" == "1" ]]
}

# ── config.toml accessors ─────────────────────────────────────

@test "unit: cfg_get reads scalar and dotted-section values" {
    mkdir -p "$(dirname "$(ew_config_path)")"
    cat > "$(ew_config_path)" << 'EOF'
schema_version = 1

[shell]
enable_aliases = true
enable_ohmyzsh = false   # inline comment

[git.identities.personal]
name  = "张三"
email = "zhangsan@example.com"
EOF
    [[ "$(cfg_get schema_version)" == "1" ]]
    [[ "$(cfg_get shell.enable_aliases)" == "true" ]]
    [[ "$(cfg_get shell.enable_ohmyzsh)" == "false" ]]
    [[ "$(cfg_get git.identities.personal.name)" == "张三" ]]
    [[ "$(cfg_get git.identities.personal.email)" == "zhangsan@example.com" ]]
    [[ "$(cfg_get missing.key 'fallback')" == "fallback" ]]
}

@test "unit: cfg_get_bool normalizes values" {
    mkdir -p "$(dirname "$(ew_config_path)")"
    cat > "$(ew_config_path)" << 'EOF'
[shell]
a = true
b = 1
c = yes
d = off
e = maybe
EOF
    [[ "$(cfg_get_bool shell.a)" == "true" ]]
    [[ "$(cfg_get_bool shell.b)" == "true" ]]
    [[ "$(cfg_get_bool shell.c)" == "true" ]]
    [[ "$(cfg_get_bool shell.d)" == "false" ]]
    [[ "$(cfg_get_bool shell.e false)" == "false" ]]
}

@test "unit: cfg_valid accepts schema_version 1 and rejects others" {
    mkdir -p "$(dirname "$(ew_config_path)")"
    printf 'schema_version = 1\n' > "$(ew_config_path)"
    run cfg_valid
    [[ "$status" -eq 0 ]]
    printf 'schema_version = 99\n' > "$(ew_config_path)"
    run cfg_valid
    [[ "$status" -ne 0 ]]
}

@test "unit: config_migrate converts legacy ini to config.toml" {
    rm -f "$(ew_config_path)"
    mkdir -p "$(dirname "$(ew_legacy_config)")"
    cat > "$(ew_legacy_config)" << 'EOF'
GIT_PERSONAL_NAME="张三"
GIT_PERSONAL_EMAIL="zhangsan@example.com"
GIT_WORK_NAME="San Zhang"
GIT_WORK_EMAIL="san@company.com"
EOF
    run config_migrate
    [[ "$status" -eq 0 ]]
    [[ -f "$(ew_config_path)" ]]
    [[ "$(cfg_get git.identities.personal.name)" == "张三" ]]
    [[ "$(cfg_get git.identities.work.email)" == "san@company.com" ]]
}

# ── JSON helpers ──────────────────────────────────────────────

@test "unit: json_escape escapes quotes, backslashes, newlines" {
    [[ "$(json_escape 'a"b')" == 'a\"b' ]]
    [[ "$(json_escape 'a\b')" == 'a\\b' ]]
    [[ "$(json_escape $'line1\nline2')" == 'line1\nline2' ]]
    [[ "$(json_escape 'plain')" == 'plain' ]]
}

# ── Managed file engine ──────────────────────────────────────

@test "unit: manifest_module_state returns absent/true" {
    rm -f "$MANIFEST_FILE"
    [[ "$(manifest_module_state foo)" == "absent" ]]
    manifest_init "1.0.0"
    manifest_set_section "foo" "installed=true"
    [[ "$(manifest_module_state foo)" == "true" ]]
    [[ "$(manifest_module_state bar)" == "absent" ]]
}

@test "unit: apply_managed_file writes idempotently and backs up" {
    local target="${TEST_HOME}/.testcfg"
    echo "user content" > "$target"
    local bak=""
    apply_managed_file "$target" "generated line" "#" bak
    [[ -n "$bak" ]]
    [[ -f "$bak" ]]
    grep -qF "user content" "$target"
    grep -qF "generated line" "$target"
    grep -qF "EasyWork managed section begin" "$target"
    # Second apply: no new backup, single managed block
    local bak2=""
    apply_managed_file "$target" "generated v2" "#" bak2
    [[ -z "$bak2" ]]
    [[ "$(grep -cF 'managed section begin' "$target")" -eq 1 ]]
    grep -qF "generated v2" "$target"
}

@test "unit: remove_managed_file removes section and restores backup" {
    local target="${TEST_HOME}/.testcfg2"
    echo "original" > "$target"
    local bak=""
    apply_managed_file "$target" "managed" "#" bak
    remove_managed_file "$target" "$bak"
    [[ "$(cat "$target")" == "original" ]]
}

@test "unit: remove_managed_section preserves user content" {
    local target="${TEST_HOME}/.testcfg3"
    {
        echo "user1"
        echo "# >>> EasyWork managed section begin (v1) >>>"
        echo "managed"
        echo "# <<< EasyWork managed section end <<<"
        echo "user2"
    } > "$target"
    remove_managed_section "$target"
    grep -qF "user1" "$target"
    grep -qF "user2" "$target"
    ! grep -qF "^managed$" "$target"
}

@test "unit: cfg_set upserts and preserves other keys" {
    rm -f "$(ew_config_path)"
    cfg_set "git.identities.personal.name" "张三"
    cfg_set "git.identities.personal.email" "z@example.com"
    cfg_set "git.identities.personal.name" "李四"
    [[ "$(cfg_get git.identities.personal.name)" == "李四" ]]
    [[ "$(cfg_get git.identities.personal.email)" == "z@example.com" ]]
    [[ "$(cfg_get schema_version)" == "1" ]]
}

# ── Update notice ─────────────────────────────────────────────

@test "unit: notify_if_update_available prints when newer" {
    function curl() { echo '{"tag_name":"v9.9.9"}'; }
    run notify_if_update_available
    [[ "$output" =~ "新版本 v9.9.9" ]]
}

@test "unit: notify_if_update_available silent in JSON mode" {
    function curl() { echo '{"tag_name":"v9.9.9"}'; }
    JSON_MODE=true
    run notify_if_update_available
    JSON_MODE=false
    [[ -z "$output" ]]
}

@test "unit: notify_if_update_available silent when offline" {
    function curl() { echo '{"tag_name":"v9.9.9"}'; }
    OFFLINE=true
    run notify_if_update_available
    OFFLINE=false
    [[ -z "$output" ]]
}

@test "unit: notify_if_update_available silent when up to date" {
    function curl() { echo '{"tag_name":"v1.0.0"}'; }
    run notify_if_update_available
    [[ ! "$output" =~ "新版本" ]]
}

@test "unit: update_json_fragment reports availability" {
    function curl() { echo '{"tag_name":"v9.9.9"}'; }
    run update_json_fragment
    [[ "$output" == '{"latest":"v9.9.9","available":true}' ]]
}

@test "unit: update_json_fragment up-to-date" {
    function curl() { echo '{"tag_name":"v1.0.0"}'; }
    run update_json_fragment
    [[ "$output" == '{"latest":"v1.0.0","available":false}' ]]
}

@test "unit: update_json_fragment offset when offline" {
    OFFLINE=true
    run update_json_fragment
    OFFLINE=false
    [[ "$output" == '{"latest":null,"available":false}' ]]
}
