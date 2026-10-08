#!/usr/bin/env bats
# ai-tools module tests: install AI coding CLIs via npm

setup() {
    load helpers/mocks
    setup_mocks
    EASYWORK_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "${EASYWORK_ROOT}/lib/common.sh"
    source "${EASYWORK_ROOT}/lib/ai-tools.sh"
    exec < /dev/null # never inherit the developer's tty
}

teardown() { teardown_mocks; }

@test "module: ai-tools: variables and module_check" {
    [[ "$MODULE_NAME" == "ai-tools" ]]
    function has_cmd() {
        case "$1" in claude | codex | pi) return 1 ;; *) return 0 ;; esac
    }
    run module_check
    [[ "$status" -ne 0 ]]
}

@test "module: ai-tools: installs missing tools via npm" {
    function has_cmd() {
        case "$1" in claude | codex | pi) return 1 ;; *) return 0 ;; esac
    }
    function npm() {
        echo "MOCK_NPM: $*" >> "${TEST_HOME}/npm.log"
        return 0
    }
    run module_install
    [[ "$status" -eq 0 ]]
    [[ "$(grep -c 'install -g' "${TEST_HOME}/npm.log")" -eq 3 ]]
    grep -qF "@anthropic-ai/claude-code" "${TEST_HOME}/npm.log"
    grep -qF "@openai/codex" "${TEST_HOME}/npm.log"
    grep -qF "@earendil-works/pi-coding-agent" "${TEST_HOME}/npm.log"
    grep -qF "tools=claude,codex,pi" "$MANIFEST_FILE"
}

@test "module: ai-tools: skips when all installed" {
    function has_cmd() { return 0; }
    function npm() {
        echo "MOCK_NPM: $*" >> "${TEST_HOME}/npm.log"
        return 0
    }
    run module_install
    [[ "$status" -eq 0 ]]
    [[ ! -f "${TEST_HOME}/npm.log" ]]
}

@test "module: ai-tools: warns when npm missing" {
    function has_cmd() {
        case "$1" in claude | codex | pi | npm) return 1 ;; *) return 0 ;; esac
    }
    run module_install
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "未找到 npm" ]]
}

@test "module: ai-tools: offline skips install" {
    function has_cmd() { return 1; }
    OFFLINE=true
    run module_install
    OFFLINE=false
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "离线模式" ]]
}

@test "module: ai-tools: dry-run does not install" {
    function has_cmd() {
        case "$1" in claude | codex | pi) return 1 ;; *) return 0 ;; esac
    }
    function npm() {
        echo "MOCK_NPM: $*" >> "${TEST_HOME}/npm.log"
        return 0
    }
    DRY_RUN=true
    run module_install
    DRY_RUN=false
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "DRY-RUN" ]]
    [[ ! -f "${TEST_HOME}/npm.log" ]]
}

@test "module: ai-tools: config can disable install" {
    function has_cmd() {
        case "$1" in claude | codex | pi) return 1 ;; *) return 0 ;; esac
    }
    function npm() {
        echo "MOCK_NPM: $*" >> "${TEST_HOME}/npm.log"
        return 0
    }
    cfg_set "ai_tools.install" "false"
    run module_install
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "已禁用" ]]
    [[ ! -f "${TEST_HOME}/npm.log" ]]
}
