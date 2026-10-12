#!/usr/bin/env bash
# EasyWork — 迁移期一键验收（M0–M7）
#
# 在本地依次执行可自动化的验收项，最后打印 PASS/FAIL/SKIP 汇总。
# 退出码：0 表示无 FAIL（SKIP 不算失败）。
#
# 用法: scripts/acceptance.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
SKIP=0

have() { command -v "$1" > /dev/null 2>&1; }

step() {
    local name="$1"
    shift
    printf '▶ %-42s ' "$name"
    if "$@" > "$TMP/last.log" 2>&1; then
        printf 'PASS\n'
        PASS=$((PASS + 1))
    else
        printf 'FAIL\n'
        FAIL=$((FAIL + 1))
        sed 's/^/      /' "$TMP/last.log" | tail -20
    fi
}

skip() {
    printf '～ %-42s SKIP (%s)\n' "$1" "$2"
    SKIP=$((SKIP + 1))
}

shell_sources() {
    local f
    for f in bin/easywork lib/*.sh tests/helpers/mocks.bash bootstrap.sh \
        tests/conformance/run.sh tests/conformance/helpers.bash scripts/*.sh; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done
}

# ── 静态检查 ────────────────────────────────────────────────
run_shellcheck() {
    # 路径无空格；不使用 mapfile 以兼容 bash 3.2
    # shellcheck disable=SC2046
    shellcheck $(shell_sources)
}

run_shfmt() { shfmt -d -i 4 -bn -ci -sr .; }

# ── 单元测试 ────────────────────────────────────────────────
run_bats() { bash tests/run.sh; }

run_gotest() { go vet ./... && go test ./...; }

# ── 黑盒 conformance（Bash + Go 字节等价） ──────────────────
run_conformance() { bash tests/conformance/run.sh all; }

# ── 交叉编译矩阵（M5 发布目标） ─────────────────────────────
_cross_once() {
    local t os arch out rel="$TMP/rel"
    mkdir -p "$rel"
    for t in darwin/amd64 darwin/arm64 linux/amd64 linux/arm64 windows/amd64 windows/arm64; do
        os="${t%%/*}"
        arch="${t##*/}"
        out="$rel/easywork_0.0.0_${os}_${arch}"
        [[ "$os" == "windows" ]] && out="${out}.exe"
        GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 go build -trimpath \
            -ldflags "-s -w -X github.com/EasyIndie/EasyWork/internal/version.Version=0.0.0" \
            -o "$out" ./cmd/ew || return 1
    done
}

# Go 链接器偶发因构建缓存损坏而 panic；失败时清缓存重试一次。
run_cross() {
    _cross_once && return 0
    echo "  （首次失败，清理构建缓存后重试）" >&2
    go clean -cache
    _cross_once
}

# ── update 自升级端到端（本地镜像） ───────────────────────
run_update_e2e() { bash scripts/update-e2e.sh > /dev/null; }

# ── Go 引擎端到端冒烟（当前平台） ───────────────────────────
run_e2e() {
    local bin="$TMP/ew-e2e"
    go build -o "$bin" ./cmd/ew || return 1
    local home="$TMP/e2e-home"
    mkdir -p "$home"
    local env=(env "HOME=$home" "EASYWORK_HOME=$home/.easywork" "EASYWORK_API_URL=http://127.0.0.1:1/")
    "${env[@]}" "$bin" status --json --offline | grep -q '"ok":true' || return 1
    "${env[@]}" "$bin" install git shell --yes --offline > /dev/null || return 1
    grep -q 'managed section' "$home/.gitconfig" || return 1
    "${env[@]}" "$bin" uninstall git shell --yes --offline > /dev/null || return 1
    grep -q 'managed section' "$home/.gitconfig" && return 1
    return 0
}

echo "== EasyWork 迁移期验收 =="
echo ""

if have shellcheck; then
    step "ShellCheck" run_shellcheck
else
    skip "ShellCheck" "未安装 shellcheck"
fi

if have shfmt; then
    step "shfmt（仓库级格式）" run_shfmt
else
    skip "shfmt" "未安装 shfmt"
fi

step "BATS（Bash 单元/集成）" run_bats

if have go; then
    step "Go vet + 单元测试" run_gotest
else
    skip "Go vet + 单元测试" "未安装 go"
fi

if have bats && have go; then
    step "Conformance（Bash ↔ Go，57×2）" run_conformance
else
    skip "Conformance" "需要 bats 与 go"
fi

if have go; then
    step "交叉编译矩阵（6 目标）" run_cross
    step "Go 引擎端到端冒烟" run_e2e
    if have python3; then
        step "update 自升级（本地镜像）" run_update_e2e
    else
        skip "update 自升级（本地镜像）" "需要 python3"
    fi
else
    skip "交叉编译矩阵" "未安装 go"
    skip "Go 引擎端到端冒烟" "未安装 go"
fi

echo ""
printf '汇总: PASS=%d  FAIL=%d  SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
if [[ "$FAIL" -gt 0 ]]; then
    echo "验收未通过"
    exit 1
fi
echo "验收通过（Windows 原生 + Go conformance 见 CI 的 go-engine/cross-compile 任务）"
