#!/usr/bin/env bats
# Tests for non-interactive mode and standalone usage

setup() {
    load helpers/mocks
    setup_mocks
    EASYWORK_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "${EASYWORK_ROOT}/lib/common.sh"
    source "${EASYWORK_ROOT}/lib/shell.sh"
    source "${EASYWORK_ROOT}/lib/git.sh"
}

teardown() {
    teardown_mocks
}

# ── EASYWORK_VERSION default ────────────────────────────────

@test "noninteractive: EASYWORK_VERSION has a default value" {
    [[ -n "${EASYWORK_VERSION:-}" ]]
    [[ "$EASYWORK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── --yes mode ──────────────────────────────────────────────

@test "noninteractive: YES_MODE=true skips shell prompts" {
    YES_MODE=true
    DRY_RUN=true
    module_install
    [[ "$?" -eq 0 ]]
}

@test "noninteractive: git identity defaults to personal with --yes" {
    YES_MODE=true
    # Setup minimal config with placeholder identities
    cat > "$CONFIG_FILE" << 'EOF'
GIT_PERSONAL_NAME="Test Person"
GIT_PERSONAL_EMAIL="test@example.com"
GIT_WORK_NAME=""
GIT_WORK_EMAIL=""
EOF
    config_load

    # _select_identity should use choice "1" (personal) in non-interactive mode
    run _select_identity
    [[ "$status" -eq 0 ]]
}

@test "noninteractive: git installs aliases without identity (no blocking)" {
    source "${EASYWORK_ROOT}/lib/git.sh"
    YES_MODE=true
    DRY_RUN=false
    unset GIT_PERSONAL_NAME GIT_PERSONAL_EMAIL GIT_WORK_NAME GIT_WORK_EMAIL
    echo "# empty" > "$CONFIG_FILE"
    config_load
    run module_install
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "跳过" ]]
    # Aliases are still written even without a configured identity
    [[ -f "$GIT_CONFIG_FILE" ]]
    grep -qF "EasyWork managed section" "$GIT_CONFIG_FILE"
    ! grep -qF "[user]" "$GIT_CONFIG_FILE"
}

# ── --verbose flag ──────────────────────────────────────────

@test "noninteractive: VERBOSE mode does not crash" {
    # Re-source shell module so module_install is shell's version
    source "${EASYWORK_ROOT}/lib/shell.sh"
    YES_MODE=true
    VERBOSE=true
    DRY_RUN=true
    module_install
    [[ "$?" -eq 0 ]]
}

# ── --config flag ───────────────────────────────────────────

@test "noninteractive: custom config path is respected" {
    local custom_config="${TEST_HOME}/custom_config"
    cat > "$custom_config" << 'EOF'
GIT_PERSONAL_NAME="Custom User"
GIT_PERSONAL_EMAIL="custom@example.com"
EOF
    CONFIG_FILE="$custom_config"
    config_load
    [[ "$GIT_PERSONAL_NAME" == "Custom User" ]]
    [[ "$GIT_PERSONAL_EMAIL" == "custom@example.com" ]]
}

# ── Default behaviors ───────────────────────────────────────

@test "noninteractive: DRY_RUN mode prevents file changes" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    DRY_RUN=true
    YES_MODE=true
    rm -f "$SH_CONFIG_FILE"
    module_install
    [[ ! -f "$SH_CONFIG_FILE" ]]
}

@test "noninteractive: module_install in real mode creates managed file" {
    source "${EASYWORK_ROOT}/lib/shell.sh"
    DRY_RUN=false
    YES_MODE=true
    rm -f "$SH_CONFIG_FILE"
    mkdir -p "$(dirname "$SH_CONFIG_FILE")"
    module_install
    [[ -f "$SH_CONFIG_FILE" ]]
    grep -qF "# >>> EasyWork managed section" "$SH_CONFIG_FILE"
}
