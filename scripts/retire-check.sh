#!/usr/bin/env bash
# EasyWork — Bash 退役前置检查
#
# 断言「冻结 Bash、退役倒计时」的前置条件（见 docs/RETIREMENT.md）。
# 退出码 0 表示可退役；非 0 表示仍有未满足项。
#
# 用法: scripts/retire-check.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

FAIL=0
ok() { printf '  ✓ %s\n' "$1"; }
bad() {
    printf '  ✗ %s\n' "$1"
    FAIL=1
}

echo "== Bash 退役前置检查 =="

# 1. Go 构建与单测
if go build ./... 2> /dev/null; then ok "go build"; else bad "go build"; fi
if go test ./... > /dev/null 2>&1; then ok "go test ./..."; else bad "go test ./..."; fi

# 2. conformance 对 Bash 与 Go 均全绿
if bash tests/conformance/run.sh all > /tmp/retire-conformance.log 2>&1; then
    ok "conformance（Bash + Go）"
else
    bad "conformance（Bash + Go）；日志: /tmp/retire-conformance.log"
fi

# 3. 版本单一来源
if grep -rqE 'EASYWORK_VERSION="[0-9]' bin lib 2> /dev/null; then
    bad "Bash 仍存在硬编码版本"
else
    ok "版本单一来源（bin/lib 无硬编码）"
fi
if [[ -f VERSION ]]; then bad "VERSION 文件仍存在"; else ok "无 VERSION 文件"; fi

# 4. Go 唯一入口 bootstrap.sh 可用
if bash -n bootstrap.sh; then ok "bootstrap.sh 语法"; else bad "bootstrap.sh 语法"; fi

# 5. release 流水线基于 Go 构建
if grep -q "go build" .github/workflows/release.yml 2> /dev/null; then
    ok "release.yml 使用 Go 构建"
else
    bad "release.yml 未使用 Go 构建"
fi

# 6. make install 安装 Go 二进制（委托 scripts/install.sh；不得再装 Bash 版）
install_block="$(awk '/^install:/{f=1} f{print} f&&/^[[:space:]]*$/{exit}' Makefile)"
if grep -q 'scripts/install.sh' <<< "$install_block" \
    && grep -q '\.build/ew' scripts/install.sh \
    && ! grep -qE '(^|[[:space:]])bin/easywork([[:space:]]|$)' scripts/install.sh; then
    ok "make install 安装 Go 二进制（跨平台）"
else
    bad "make install 未正确安装 Go 二进制"
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "结论: 满足退役前置条件（执行前仍需 ≥2 release 无回滚）"
else
    echo "结论: 暂不满足（见上）"
fi
exit "$FAIL"
