#!/usr/bin/env bash
# EasyWork — update 自升级端到端验收（本地镜像源）
#
# 步骤：构建“旧版本”二进制 → 用本地 HTTP 镜像提供“新版本”归档 + checksums.txt
#      + latest.json → 运行 `ew update --yes` → 断言二进制被替换为新版本。
#
# 用法: scripts/update-e2e.sh
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"

OLD_VER="0.1.0"
NEW_VER="0.2.0"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
    darwin | linux) : ;;
    *)
        echo "仅支持 macOS/Linux 本地端到端（Windows 见 CI/实机）" >&2
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

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
mirror="$work/mirror"
entry="$mirror/$NEW_VER"
mkdir -p "$entry" "$work/bin"

echo "== 构建旧版本 $OLD_VER =="
go build -trimpath -ldflags "-X github.com/EasyIndie/EasyWork/internal/version.Version=$OLD_VER" \
    -o "$work/bin/ew" ./cmd/ew

echo "== 构建新版本 $NEW_VER =="
go build -trimpath -ldflags "-X github.com/EasyIndie/EasyWork/internal/version.Version=$NEW_VER" \
    -o "$work/new-ew" ./cmd/ew

echo "== 制作发布资产 =="
asset="easywork_${NEW_VER}_${os}_${arch}.tar.gz"
(cd "$work" && cp new-ew ew && tar czf "$entry/$asset" ew)
(cd "$entry" && shasum -a 256 "$asset" > checksums.txt)
printf '{"tag_name":"%s"}\n' "$NEW_VER" > "$mirror/latest.json"

echo "== 启动本地镜像 (:${port}) =="
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$mirror" > "$work/httpd.log" 2>&1 &
server_pid="$!"
# 冷启动 runner 上 HTTP 服务可能 >1s 才可用：轮询就绪，失败时打印日志
i=0
while ! curl -fsS -o /dev/null "http://127.0.0.1:${port}/latest.json"; do
    i=$((i + 1))
    if [[ $i -ge 50 ]]; then
        cat "$work/httpd.log" >&2
        echo "本地镜像启动失败（:${port}）" >&2
        exit 1
    fi
    sleep 0.2
done

home="$work/home"
mkdir -p "$home"

echo "== 运行 update =="
HOME="$home" \
    EASYWORK_HOME="$home/.easywork" \
    EASYWORK_API_URL="http://127.0.0.1:${port}/latest.json" \
    EASYWORK_RELEASE_URL="http://127.0.0.1:${port}" \
    EASYWORK_UPDATE_SKIP_REINSTALL=true \
    "$work/bin/ew" update --yes

echo "== 校验升级结果 =="
got="$(HOME="$home" EASYWORK_HOME="$home/.easywork" "$work/bin/ew" version --json --offline \
    | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
echo "安装版本: $got"
[[ "$got" == "$NEW_VER" ]] || {
    echo "FAIL: 期望 $NEW_VER，实际 $got" >&2
    exit 1
}
echo "✅ update 自升级端到端通过（${OLD_VER} → ${NEW_VER}）"
