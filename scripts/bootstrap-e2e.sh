#!/usr/bin/env bash
# EasyWork — bootstrap.sh 端到端验收（本地镜像源，不触网）
#
# 覆盖退役后 Unix 唯一安装入口的三条关键路径：
#   1. 指定版本安装（EASYWORK_VERSION）
#   2. 通过 API 解析 latest 后安装（无 EASYWORK_VERSION）
#   3. 归档被篡改 → sha256 校验失败且不覆盖已安装二进制
#
# 用法: scripts/bootstrap-e2e.sh
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
VER="0.9.9"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
    darwin | linux) : ;;
    *)
        echo "仅支持 macOS/Linux 本地端到端（Windows 用 bootstrap.ps1，见 CI/实机）" >&2
        exit 1
        ;;
esac
arch="$(uname -m)"
case "$arch" in
    x86_64 | amd64) arch="amd64" ;;
    arm64 | aarch64) arch="arm64" ;;
esac

work="$(mktemp -d)"
server_pid=""
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2> /dev/null || true
        wait "$server_pid" 2> /dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "  ✗ $*" >&2
    exit 1
}
ok() { echo "  ✓ $*"; }

free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

# ── 制作一个「发布」镜像（含 checksums.txt 与 latest API 模拟） ──
make_mirror() {
    local dir="$1"
    local asset="easywork_${VER}_${os}_${arch}.tar.gz"
    mkdir -p "$dir/$VER" "$dir/repos/EasyIndie/EasyWork/releases"
    (cd "$dir" && cp "$work/ew" ew && tar czf "$dir/$VER/$asset" ew && rm -f ew)
    (cd "$dir/$VER" && shasum -a 256 "$asset" > checksums.txt)
    printf '{"tag_name":"%s"}\n' "$VER" > "$dir/repos/EasyIndie/EasyWork/releases/latest"
}

start_server() {
    local dir="$1" port="$2"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir" > "$work/httpd-$port.log" 2>&1 &
    server_pid="$!"
    sleep 1
}

echo "== 构建待发布二进制 $VER =="
go build -trimpath -ldflags "-X github.com/EasyIndie/EasyWork/internal/version.Version=$VER" \
    -o "$work/ew" ./cmd/ew

mirror="$work/mirror"
make_mirror "$mirror"
port="$(free_port)"
start_server "$mirror" "$port"
base="http://127.0.0.1:${port}"

install_dir="$work/bin"
mkdir -p "$install_dir"
export HOME="$work/home"
mkdir -p "$HOME"

echo "== 1. 指定版本安装 =="
EASYWORK_VERSION="$VER" \
    EASYWORK_BIN_DIR="$install_dir" \
    EASYWORK_DOWNLOAD_BASE="$base" \
    bash "$ROOT/bootstrap.sh" > "$work/run1.log" 2>&1 || {
    cat "$work/run1.log" >&2
    fail "bootstrap 失败（指定版本）"
}
[[ -x "$install_dir/ew" ]] || fail "未安装 ew"
got="$("$install_dir/ew" version --json --offline | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
[[ "$got" == "$VER" ]] || fail "版本不符: 期望 $VER，实际 $got"
[[ -e "$install_dir/easywork" ]] || fail "缺少 easywork 兼容别名"
"$install_dir/ew" status --json --offline | grep -q '"ok":true' || fail "安装后 ew status 不可用"
ok "指定版本安装 + 别名 + status 可用"

echo "== 2. 无 EASYWORK_VERSION（经 API 解析 latest） =="
rm -f "$install_dir/ew"
EASYWORK_BIN_DIR="$install_dir" \
    EASYWORK_DOWNLOAD_BASE="$base" \
    EASYWORK_API_BASE="$base" \
    bash "$ROOT/bootstrap.sh" > "$work/run2.log" 2>&1 || {
    cat "$work/run2.log" >&2
    fail "bootstrap 失败（latest 解析）"
}
got="$("$install_dir/ew" version --json --offline | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
[[ "$got" == "$VER" ]] || fail "latest 解析后版本不符: 期望 $VER，实际 $got"
grep -q "完整性校验通过" "$work/run2.log" || fail "未执行 sha256 校验"
ok "latest 解析安装 + sha256 校验"

echo "== 3. 归档被篡改 → 必须失败且不覆盖已装版本 =="
tamper="$work/tamper"
cp -R "$mirror" "$tamper"
asset="easywork_${VER}_${os}_${arch}.tar.gz"
printf 'tampered' >> "$tamper/$VER/$asset" # 破坏归档，checksums.txt 不变
port2="$(free_port)"
kill "$server_pid" 2> /dev/null || true
wait "$server_pid" 2> /dev/null || true
start_server "$tamper" "$port2"

if EASYWORK_VERSION="$VER" \
    EASYWORK_BIN_DIR="$install_dir" \
    EASYWORK_DOWNLOAD_BASE="http://127.0.0.1:${port2}" \
    bash "$ROOT/bootstrap.sh" > "$work/run3.log" 2>&1; then
    cat "$work/run3.log" >&2
    fail "篡改归档竟然安装成功（校验未生效）"
fi
grep -qi "校验失败" "$work/run3.log" || fail "失败原因不是校验失败: $(cat "$work/run3.log")"
got="$("$install_dir/ew" version --json --offline | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
[[ "$got" == "$VER" ]] || fail "损坏下载覆盖了已安装二进制（版本变为 $got）"
ok "篡改归档被拦截，已装二进制未被覆盖"

echo "✅ bootstrap 端到端通过（指定版本 / latest 解析 / 篡改拦截）"
