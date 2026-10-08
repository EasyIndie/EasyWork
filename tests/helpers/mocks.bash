#!/usr/bin/env bash
# EasyWork — Test Helpers & Mocks

# ── Setup / Teardown ─────────────────────────────────────────
# EasyWork variables expected by modules
export EASYWORK_VERSION="1.0.0"
export DRY_RUN=false
export YES_MODE=false
export VERBOSE=false

# Mock functions that modules call but tests shouldn't execute
# shellcheck disable=SC2329  # mock functions are invoked via export -f in subprocesses
setup_mocks() {
    # Ignore any EASYWORK_* env leaking from the developer's shell so paths
    # derive from the per-test $HOME below.
    unset EASYWORK_HOME EASYWORK_RAW_URL EASYWORK_RELEASE_URL EASYWORK_API_URL EASYWORK_WEB_URL
    # Unique temp HOME per test: keeps tests isolated and makes parallel
    # execution (across files) safe.
    TEST_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/easywork.XXXXXX")"
    export TEST_HOME
    export HOME="${TEST_HOME}"
    mkdir -p "${TEST_HOME}"

    # Override manifest and config paths
    export MANIFEST_FILE="${TEST_HOME}/.easywork/manifest"
    export CONFIG_FILE="${TEST_HOME}/.easywork/config"
    export SH_CONFIG_FILE="${TEST_HOME}/.sh_config_custom"
    export GIT_CONFIG_FILE="${TEST_HOME}/.gitconfig"
    export VIMRC_FILE="${TEST_HOME}/.vimrc"
    export VIM_DIR="${TEST_HOME}/.vim"
    export TEMP_DIR="${TEST_HOME}/tmp"
    mkdir -p "${TEMP_DIR}"
    mkdir -p "${TEST_HOME}/.easywork"
    export TMPDIR="${TEMP_DIR}"

    # Mock curl: capture calls instead of making real network requests
    # shellcheck disable=SC2329
    function curl() {
        echo "MOCK_CURL: $*" >> "${TEST_HOME}/mock_curl.log"
        return 0
    }

    # Mock git for non-destructive testing
    # shellcheck disable=SC2329
    function git() {
        case "${1:-}" in
            config)
                echo "mock-value"
                ;;
            symbolic-ref)
                echo "main"
                ;;
            --version)
                echo "git version 2.40.0"
                ;;
            *)
                echo "MOCK_GIT: $*" >> "${TEST_HOME}/mock_git.log"
                ;;
        esac
        return 0
    }

    # Mock vim for non-interactive testing
    # shellcheck disable=SC2329
    function vim() {
        echo "MOCK_VIM: $*" >> "${TEST_HOME}/mock_vim.log"
        return 0
    }

    # Mock brew
    # shellcheck disable=SC2329
    function brew() {
        echo "MOCK_BREW: $*" >> "${TEST_HOME}/mock_brew.log"
        return 0
    }

    # Mock sudo
    # shellcheck disable=SC2329
    function sudo() {
        shift || true
        echo "MOCK_SUDO: $*" >> "${TEST_HOME}/mock_sudo.log"
        return 0
    }

    # Mock node
    # shellcheck disable=SC2329
    function node() {
        echo "v18.0.0"
        return 0
    }

    # Mock networksetup (macOS)
    # shellcheck disable=SC2329
    function networksetup() {
        echo "MOCK_NETWORKSETUP: $*" >> "${TEST_HOME}/mock_networksetup.log"
        return 0
    }

    # Mock scutil (macOS)
    # shellcheck disable=SC2329
    function scutil() {
        echo "MOCK_SCUTIL: $*" >> "${TEST_HOME}/mock_scutil.log"
        return 0
    }

    # Mock GitHub CLI + AI CLIs as "already installed" so their modules skip
    # installation (tests never hit the network / real package managers).
    # shellcheck disable=SC2329
    function npm() {
        echo "MOCK_NPM: $*" >> "${TEST_HOME}/mock_npm.log"
        return 0
    }
    # shellcheck disable=SC2329
    function gh() { return 0; }
    # shellcheck disable=SC2329
    function claude() { return 0; }
    # shellcheck disable=SC2329
    function codex() { return 0; }
    # shellcheck disable=SC2329
    function pi() { return 0; }

    export -f curl git vim brew sudo node networksetup scutil npm gh claude codex pi 2> /dev/null || true
}

teardown_mocks() {
    rm -rf "${TEST_HOME}"
}
