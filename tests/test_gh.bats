#!/usr/bin/env bats
# gh module tests: install GitHub CLI

setup() {
    load helpers/mocks
    setup_mocks
    EASYWORK_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "${EASYWORK_ROOT}/lib/common.sh"
    source "${EASYWORK_ROOT}/lib/gh.sh"
    exec < /dev/null # never inherit the developer's tty
}

teardown() { teardown_mocks; }

@test "module: gh: variables and module_check" {
    [[ "$MODULE_NAME" == "gh" ]]
    function has_cmd() { [[ "$1" != "gh" ]]; }
    run module_check
    [[ "$status" -ne 0 ]]
}

@test "module: gh: skips when already installed" {
    function has_cmd() { [[ "$1" == "gh" ]]; }
    function gh() { echo "gh version 2.0.0"; }
    function brew() {
        echo "MOCK_BREW: $*" >> "${TEST_HOME}/brew.log"
        return 0
    }
    run module_install
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "已安装" ]]
    [[ ! -f "${TEST_HOME}/brew.log" ]]
}

@test "module: gh: installs via detected package manager" {
    function has_cmd() { [[ "$1" != "gh" ]]; }
    function detect_pkg_manager() { echo "brew"; }
    function brew() {
        echo "MOCK_BREW: $*" >> "${TEST_HOME}/brew.log"
        return 0
    }
    run module_install
    [[ "$status" -eq 0 ]]
    grep -qF "install gh" "${TEST_HOME}/brew.log"
}

@test "module: gh: dry-run does not install" {
    function has_cmd() { [[ "$1" != "gh" ]]; }
    function brew() {
        echo "MOCK_BREW: $*" >> "${TEST_HOME}/brew.log"
        return 0
    }
    DRY_RUN=true
    run module_install
    DRY_RUN=false
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "DRY-RUN" ]]
    [[ ! -f "${TEST_HOME}/brew.log" ]]
}

@test "module: gh: offline skips install" {
    function has_cmd() { [[ "$1" != "gh" ]]; }
    OFFLINE=true
    run module_install
    OFFLINE=false
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "离线模式" ]]
}
