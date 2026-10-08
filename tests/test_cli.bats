#!/usr/bin/env bats
# Tests for CLI routing and global flags

setup() {
    load helpers/mocks
    setup_mocks
    exec < /dev/null # never inherit the developer's tty
}

teardown() { teardown_mocks; }

@test "cli: help outputs usage" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" help
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "EasyWork" ]]
    [[ "$output" =~ "install" ]]
    [[ "$output" =~ "shell" ]]
    [[ "$output" =~ "git" ]]
    [[ "$output" =~ "vim" ]]
}

@test "cli: version shows version" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" version
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "EasyWork 0" ]]
}

@test "cli: unknown command shows help" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" nonexistent_command
    [[ "$status" -ne 0 ]]
}

@test "cli: --help flag works" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" --help
    [[ "$output" =~ "EasyWork" ]]
}

@test "cli: --dry-run flag is accepted" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" install --dry-run --yes
    [[ "$status" -eq 0 ]]
}

@test "cli: --yes flag skips prompts" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" install --dry-run --yes
    [[ "$status" -eq 0 ]]
}

@test "cli: config shows path" {
    run bash "${BATS_TEST_DIRNAME}/../bin/easywork" config
    [[ "$output" =~ "配置文件路径" ]] || [[ "$output" =~ ".easywork/config" ]]
}
