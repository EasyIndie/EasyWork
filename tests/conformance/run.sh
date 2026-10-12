#!/usr/bin/env bash
# EasyWork — conformance runner
#
# 用法: tests/conformance/run.sh [bash|go|all]
#   bash  仅验证 bin/easywork
#   go    构建并验证 Go 实现（cmd/ew）
#   all   先 Bash 后 Go（默认）
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT="$PWD"
IMPL="${1:-all}"
BATS="${BATS:-bats}"

_run() {
    local label="$1" bin="$2"
    echo "==> conformance [${label}] ${bin}"
    EW_BIN="$bin" EW_ENGINE="$label" "$BATS" tests/conformance/*.bats
    return $?
}

rc=0

if [[ "$IMPL" == "bash" || "$IMPL" == "all" ]]; then
    _run "bash" "${ROOT}/bin/easywork" || rc=1
fi

if [[ "$IMPL" == "go" || "$IMPL" == "all" ]]; then
    bin="${ROOT}/.build/ew"
    # Windows 上 go build -o 会产出 .exe
    if [[ "$(go env GOOS 2> /dev/null)" == "windows" ]]; then
        bin="${ROOT}/.build/ew.exe"
    fi
    mkdir -p "${ROOT}/.build"
    if (cd "$ROOT" && go build -o "$bin" ./cmd/ew); then
        _run "go" "$bin" || rc=1
    else
        echo "  构建 Go 实现失败" >&2
        rc=1
    fi
fi

exit "$rc"
