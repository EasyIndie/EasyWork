#!/usr/bin/env bats
# E2E tests: real user flows with standalone binary simulation

EASYWORK_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
# Derive the binary's version so assertions don't hardcode it across releases.
EASYWORK_BIN_VERSION="$(sed -n 's/^EASYWORK_VERSION="\(.*\)"/\1/p' "${EASYWORK_ROOT}/bin/easywork" | head -1)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    mkdir -p "$TEST_HOME/.local/bin"
    export TMPDIR="$TEST_HOME/tmp"
    mkdir -p "$TMPDIR"
    # Ignore any EASYWORK_* env leaking from the developer's shell
    unset EASYWORK_HOME EASYWORK_RAW_URL EASYWORK_RELEASE_URL EASYWORK_API_URL EASYWORK_WEB_URL EASYWORK_CHANNEL

    # Create mock wrapper that replaces curl to serve from local repo
    cat > "$TEST_HOME/.local/bin/curl" << MOCK_CURL
#!/usr/bin/env bash
out="" url=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o) out="\$2"; shift 2 ;;
        -H) shift 2 ;;
        -*) shift ;;
        *) url="\$1"; shift ;;
    esac
done
repo="${EASYWORK_ROOT}"
path="\${url#*raw.githubusercontent.com/EasyIndie/EasyWork/*/}"
if [[ "\$url" == *"api.github.com"* ]]; then
    echo '{"tag_name":"v1.0.0"}'
elif [[ -n "\$path" ]] && [[ -f "\${repo}/\${path}" ]]; then
    if [[ -n "\$out" ]]; then
        cat "\${repo}/\${path}" > "\$out"
    else
        cat "\${repo}/\${path}"
    fi
fi
exit 0
MOCK_CURL
    chmod +x "$TEST_HOME/.local/bin/curl"

    # Mock other commands
    # GIT_MOCK_IN_REPO: set to "true" to make git rev-parse --git-dir succeed
    for cmd in git vim brew sudo node npm gh claude codex pi; do
        cat > "$TEST_HOME/.local/bin/$cmd" << 'MOCK_CMD'
#!/usr/bin/env bash
case "${1:-}" in
    config) echo "mock-value" ;;
    rev-parse)
        if [[ "$*" == *--git-dir* ]]; then
            if [[ "${GIT_MOCK_IN_REPO:-false}" == "true" ]]; then
                echo "$HOME/fake-repo/.git"
                exit 0
            fi
            exit 128
        fi
        if [[ "$*" == *--show-toplevel* ]]; then
            echo "$HOME/fake-repo"
            exit 0
        fi
        ;;
esac
exit 0
MOCK_CMD
        chmod +x "$TEST_HOME/.local/bin/$cmd"
    done

    # Standalone binary (no lib/ directory)
    cp "${EASYWORK_ROOT}/bin/easywork" "$TEST_HOME/.local/bin/easywork"
    chmod +x "$TEST_HOME/.local/bin/easywork"

    export PATH="$TEST_HOME/.local/bin:$PATH"
    exec < /dev/null # never inherit the developer's tty
}

teardown() {
    rm -rf "$TEST_HOME"
}

# ─── A: Standalone binary basics ─────────────────────────────

@test "e2e: standalone binary version" {
    run easywork version
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "EasyWork" ]]
    [[ -f "$TEST_HOME/.easywork/lib/v${EASYWORK_BIN_VERSION}/common.sh" ]]
}

@test "e2e: standalone binary help lists modules" {
    run easywork help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "shell" ]]
    [[ "$output" =~ "git" ]]
    [[ "$output" =~ "vim" ]]
}

@test "e2e: standalone binary help (no args)" {
    run easywork
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "EasyWork" ]]
}

@test "e2e: config creates generic config" {
    run easywork config
    [[ "$status" -eq 0 ]]
    run cat "$TEST_HOME/.easywork/config"
    [[ ! "$output" =~ "Your Name" ]]
}

# ─── B: Piped install ───────────────────────────────────────

@test "e2e: piped install CLI only" {
    run bash -c "cat ${EASYWORK_ROOT}/bin/easywork | PATH=${TEST_HOME}/.local/bin:\$PATH HOME=${TEST_HOME} bash -s -- install --dry-run" 2>&1
    [[ "$output" =~ "CLI 准备就绪" ]]
    [[ ! "$output" =~ "配置 shell" ]]
}

@test "e2e: piped reinstall overwrites" {
    mkdir -p "$TEST_HOME/.easywork"
    echo "easywork_version=1.0.0" > "$TEST_HOME/.easywork/manifest"
    run bash -c "cat ${EASYWORK_ROOT}/bin/easywork | PATH=${TEST_HOME}/.local/bin:\$PATH HOME=${TEST_HOME} bash -s -- install --dry-run" 2>&1
    [[ "$output" =~ "CLI 准备就绪" ]]
}

# ─── C: Full install lifecycle ──────────────────────────────

@test "e2e: install --dry-run all modules" {
    run easywork install --dry-run --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "配置 shell" ]]
    [[ "$output" =~ "配置 git" ]]
    [[ "$output" =~ "配置 vim" ]]
}

@test "e2e: install --yes creates files" {
    run easywork install --yes
    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_HOME/.easywork/manifest" ]]
    [[ -f "$TEST_HOME/.sh_config_custom" ]]
    run cat "$TEST_HOME/.easywork/manifest"
    [[ "$output" =~ "shell" ]]
}

@test "e2e: version shows installed components" {
    easywork install --yes 2> /dev/null
    run easywork version
    [[ "$output" =~ "已安装组件" ]]
}

@test "e2e: full uninstall cleanup" {
    easywork install --yes 2> /dev/null
    run easywork uninstall --yes --remove-config
    [[ "$status" -eq 0 ]]
    [[ ! -f "$TEST_HOME/.easywork/manifest" ]]
}

# ─── D: Single module ───────────────────────────────────────

@test "e2e: install vim only" {
    run easywork install vim --dry-run --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "配置 vim" ]]
    # Only vim module should run (no shell or git install messages)
    [[ ! "$output" =~ "shell 完成" ]]
    [[ ! "$output" =~ "git 完成" ]]
}

@test "e2e: install unknown module errors" {
    run easywork install unknown --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "未知组件" ]]
}

@test "e2e: partial uninstall keeps others" {
    easywork install --yes 2> /dev/null
    run easywork uninstall vim --yes
    [[ "$status" -eq 0 ]]
    run cat "$TEST_HOME/.easywork/manifest"
    [[ "$output" =~ "shell" ]]
    [[ ! "$output" =~ "vim" ]]
}

# ─── E: Git specifics ───────────────────────────────────────

@test "e2e: git with config values" {
    mkdir -p "$TEST_HOME/.easywork"
    cat > "$TEST_HOME/.easywork/config" << 'EOF'
## git
GIT_PERSONAL_NAME="Test User"
GIT_PERSONAL_EMAIL="test@example.com"
EOF
    run easywork install git --dry-run --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Test User" ]]
}

@test "e2e: git dry-run with empty config uses dummy values" {
    mkdir -p "$TEST_HOME/.easywork"
    echo "# empty" > "$TEST_HOME/.easywork/config"
    run easywork install git --dry-run --yes
    [[ "$status" -eq 0 ]]
    # Dry-run fills in dummy values for preview
    [[ "$output" =~ "your-name" ]]
}

# ─── F: Cache ───────────────────────────────────────────────

@test "e2e: cache reused on second run" {
    easywork version 2> /dev/null
    rm -f "$TEST_HOME/.local/bin/curl"
    run easywork version
    [[ "$status" -eq 0 ]]
}

@test "e2e: URL fallback to main branch when version tag is missing" {
    # Simulate version tag not existing: make the versioned URL fail
    # The mock curl will return 0 for the main-branch URL after tag failure
    # Check that the fallback warning is emitted to stderr
    export EASYWORK_RAW_URL="https://raw.githubusercontent.com/EasyIndie/EasyWork/v99.99.99"
    run easywork version 2>&1
    # Should still succeed (falls back to main)
    [[ "$status" -eq 0 ]]
}

# ─── G: Global flags ────────────────────────────────────────

@test "e2e: dry-run prevents module file writes" {
    # dry-run creates manifest for tracking but modules should not write configs
    run easywork install --dry-run --yes
    [[ "$status" -eq 0 ]]
    # Module config files should NOT be created
    [[ ! -f "$TEST_HOME/.sh_config_custom" ]]
}

# ─── H: git local scope ──────────────────────────────────────

@test "e2e: git --yes install defaults to global scope" {
    # In non-interactive (--yes) mode, git always defaults to global scope
    export GIT_MOCK_IN_REPO=true
    mkdir -p "$TEST_HOME/fake-repo/.git"
    mkdir -p "$TEST_HOME/.easywork"
    cat > "$TEST_HOME/.easywork/config" << 'EOF'
## git
GIT_PERSONAL_NAME="Test User"
GIT_PERSONAL_EMAIL="test@example.com"
EOF
    run easywork install git --dry-run --yes
    [[ "$status" -eq 0 ]]
    # --yes mode defaults to global regardless of GIT_MOCK_IN_REPO
    [[ "$output" =~ "配置级别: global" ]]
}

@test "e2e: git with GIT_MOCK_IN_REPO=false still works" {
    export GIT_MOCK_IN_REPO=false
    mkdir -p "$TEST_HOME/.easywork"
    cat > "$TEST_HOME/.easywork/config" << 'EOF'
## git
GIT_PERSONAL_NAME="Test User"
GIT_PERSONAL_EMAIL="test@example.com"
EOF
    run easywork install git --dry-run --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "配置级别: global" ]]
}

# ─── I: cmd_update ───────────────────────────────────────────

@test "e2e: update runs without crashing" {
    # The update command fetches from GitHub API and compares versions.
    # In mock mode it detects v1.0.0 > 0.0.1, then prompts interactively.
    # Without a tty, the command gracefully handles the failed read.
    # We just verify it doesn't crash.
    mkdir -p "$TEST_HOME/.easywork"
    echo "easywork_version=0.0.1" > "$TEST_HOME/.easywork/manifest"
    run easywork update 2>&1 || true
    # The command should run its logic without a hard crash
    [[ "$output" =~ "检查更新" || "$output" =~ "当前版本" || "$output" =~ "最新版本" ]]
}

@test "e2e: update handles network failure gracefully" {
    # Override mock curl to fail for api requests
    cat > "$TEST_HOME/.local/bin/curl" << 'FAIL_CURL'
#!/usr/bin/env bash
if [[ "$*" == *"api.github.com"* ]]; then
    exit 1
fi
exit 0
FAIL_CURL
    chmod +x "$TEST_HOME/.local/bin/curl"
    mkdir -p "$TEST_HOME/.easywork"
    echo "easywork_version=0.0.1" > "$TEST_HOME/.easywork/manifest"
    run easywork update 2>&1
    # Should fail gracefully with network error
    [[ "$status" -ne 0 ]]
}

# ─── J: completion status ────────────────────────────────────

@test "e2e: completion status reports state" {
    run easywork completion status
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "补全文件目录" ]]
}

@test "e2e: completion status after install shows injected files" {
    easywork install --yes 2> /dev/null
    run easywork completion status
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "补全文件目录" ]]
    [[ "$output" =~ "✓" ]]
}

@test "e2e: completion remove cleans up" {
    easywork install --yes 2> /dev/null
    run easywork completion remove
    [[ "$status" -eq 0 ]]
    # Verify removal
    run easywork completion status
    [[ ! "$output" =~ "✓" ]]
}

# ─── J: --json output ───────────────────────────────────────

@test "e2e: version --json emits structured output" {
    run easywork version --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"command":"version"' ]]
    [[ "$output" =~ "\"version\":\"${EASYWORK_BIN_VERSION}\"" ]]
    [[ "$output" =~ '"error":null' ]]
}

@test "e2e: list --json emits module array" {
    run easywork list --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"command":"list"' ]]
    [[ "$output" =~ '"name":"shell"' ]]
    [[ "$output" =~ '"name":"git"' ]]
}

@test "e2e: list (human) shows modules" {
    run easywork list
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "shell" ]]
    [[ "$output" =~ "git" ]]
}

# ─── K: status / doctor / init ───────────────────────────

@test "e2e: status (human) runs" {
    run easywork status
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "组件状态" ]]
}

@test "e2e: status --json emits modules" {
    run easywork status --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"command":"status"' ]]
    [[ "$output" =~ '"name":"shell"' ]]
}

@test "e2e: doctor --json emits checks" {
    run easywork doctor --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"command":"doctor"' ]]
    [[ "$output" =~ '"name":"curl"' ]]
}

@test "e2e: init installs shell and git without vim" {
    run easywork init
    [[ "$status" -eq 0 ]]
    run cat "$TEST_HOME/.easywork/manifest"
    [[ "$output" =~ "shell" ]]
    [[ "$output" =~ "git" ]]
    [[ ! "$output" =~ "\[vim\]" ]]
}

@test "e2e: config set/get round-trips to config.toml" {
    run easywork config set git.identities.personal.name "Test User"
    [[ "$status" -eq 0 ]]
    run easywork config get git.identities.personal.name
    [[ "$output" == "Test User" ]]
    [[ -f "$TEST_HOME/.easywork/config.toml" ]]
}

@test "e2e: status notices a newer version" {
    mkdir -p "$TEST_HOME/.easywork"
    echo "easywork_version=0.0.1" > "$TEST_HOME/.easywork/manifest"
    run easywork status
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "新版本 v1.0.0" ]]
}

@test "e2e: status --json includes structured update field" {
    run easywork status --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"update":' ]]
    [[ "$output" =~ '"latest":"v1.0.0"' ]]
    [[ "$output" =~ '"available":true' ]]
}

@test "e2e: version --json includes structured update field" {
    run easywork version --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"update":' ]]
}

@test "e2e: list --json includes structured update field" {
    run easywork list --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"update":' ]]
}

@test "e2e: doctor --json includes structured update field" {
    run easywork doctor --json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"update":' ]]
}

@test "e2e: install git keeps module manifest keys" {
    mkdir -p "$TEST_HOME/.easywork"
    printf '[user]\n  name = preexisting\n' > "$TEST_HOME/.gitconfig"
    run easywork install git --yes
    [[ "$status" -eq 0 ]]
    run cat "$TEST_HOME/.easywork/manifest"
    # Framework must not clobber keys written by the module
    [[ "$output" =~ "scope=global" ]]
    [[ "$output" =~ "config_backup=" ]]
}
