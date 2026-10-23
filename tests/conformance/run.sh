#!/usr/bin/env bash
# EasyWork — Go 引擎黑盒 conformance 运行器
#
# 用法: tests/conformance/run.sh [go]
#   只测 Go 二进制（Bash 引擎已于 0.4.0 退役，存档 tag legacy-bash-0.3.0）。
#   保留参数以兼容旧脚本；非 go 的参数会给出提示后仍只跑 Go。
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT="$PWD"
IMPL="${1:-go}"
BATS="${BATS:-bats}"

case "$IMPL" in
    go | all | bash) : ;;
    *)
        echo "用法: tests/conformance/run.sh [go]" >&2
        exit 1
        ;;
esac
if [[ "$IMPL" != "go" ]]; then
    echo "提示: Bash 引擎已退役，仅验证 Go 实现" >&2
fi

echo "==> conformance [go]"
bin="${ROOT}/.build/ew"
if [[ "$(go env GOOS 2> /dev/null)" == "windows" ]]; then
    bin="${ROOT}/.build/ew.exe"
fi
mkdir -p "${ROOT}/.build"
(cd "$ROOT" && go build -o "$bin" ./cmd/ew) || {
    echo "  构建 Go 实现失败" >&2
    exit 1
}
EW_BIN="$bin" EW_ENGINE="go" "$BATS" tests/conformance/*.bats
