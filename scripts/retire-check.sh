#!/usr/bin/env bash
# EasyWork — Bash 引擎退役不变量检查
#
# Bash 引擎已于 0.4.0 退役（存档 tag `legacy-bash-0.3.0`）。
# 本脚本断言「退役后的仓库结构」没有回退：Bash 引擎文件不得复活、
# 唯一安装入口是 bootstrap.sh、conformance/release 只针对 Go。
#
# 用法: scripts/retire-check.sh   （退出码 0 = 不变量成立）
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

FAIL=0
ok() { printf '  ✓ %s\n' "$1"; }
bad() {
    printf '  ✗ %s\n' "$1"
    FAIL=1
}

echo "== Bash 退役不变量检查 =="

# 1. Bash 引擎文件不得复活
legacy_files=(bin/easywork lib/common.sh lib/install.sh MODULES easywork.conf.example tests/run.sh tests/helpers/mocks.bash)
alive=0
for f in "${legacy_files[@]}"; do
    [[ -e "$f" ]] && alive=1 && bad "残留旧文件: $f"
done
if [[ "$alive" -eq 1 ]]; then :; else ok "无 Bash 引擎残留（bin/ lib/ MODULES 旧 ini 示例）"; fi
if compgen -G "tests/test_*.bats" > /dev/null; then
    bad "仍存在 Bash 白盒测试 tests/test_*.bats"
else
    ok "无 Bash 白盒测试"
fi

# 2. 唯一 Unix 入口是 bootstrap.sh，且带完整性校验
if bash -n bootstrap.sh 2> /dev/null; then ok "bootstrap.sh 语法"; else bad "bootstrap.sh 语法"; fi
if grep -q "verify_checksum" bootstrap.sh; then ok "bootstrap.sh 校验 sha256"; else bad "bootstrap.sh 缺少校验"; fi

# 3. conformance 只针对 Go
if grep -q 'IMPL" != "go"' tests/conformance/run.sh || grep -q 'EW_ENGINE="go"' tests/conformance/run.sh; then
    ok "conformance 仅 Go"
else
    bad "conformance 仍包含 Bash 分支"
fi

# 4. 构建/发布只针对 Go
if grep -q "go build" .github/workflows/release.yml 2> /dev/null; then
    ok "release.yml 使用 Go 构建"
else
    bad "release.yml 未使用 Go 构建"
fi
if grep -q "bin/easywork\|lib/\*\.sh" .github/workflows/release.yml 2> /dev/null; then
    bad "release.yml 仍打包 Bash 资产"
else
    ok "release.yml 不含 Bash 资产"
fi
if grep -q "bin/easywork\|lib/\*\.sh" .github/workflows/ci.yml 2> /dev/null; then
    bad "ci.yml 仍检查 Bash 引擎文件"
else
    ok "ci.yml 不含 Bash 引擎步骤"
fi

# 5. Makefile 不再有 Bash 专属目标
if grep -qE "^(conform-bash|test-bash):" Makefile; then
    bad "Makefile 仍有 Bash 专属目标"
else
    ok "Makefile 无 Bash 专属目标"
fi

# 6. 代码仍可构建与测试
if go build ./... 2> /dev/null; then ok "go build"; else bad "go build"; fi
if go test ./... > /dev/null 2>&1; then ok "go test ./..."; else bad "go test ./..."; fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "结论: 退役不变量成立（Bash 引擎已彻底移除）"
else
    echo "结论: 存在残留或回退（见上）"
fi
exit "$FAIL"
