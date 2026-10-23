#!/usr/bin/env bash
# EasyWork — 跨平台引导脚本（curl | bash 入口）
#
# 作用：探测 OS/架构 → 下载对应的 EasyWork 二进制 → 安装到 PATH。
# 之后所有功能由静态二进制提供（不再下载 lib/*.sh）。
#
# 用法:
#   curl -sL https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.sh | bash
#
# 可覆盖:
#   EASYWORK_VERSION   指定版本（tag，不含前导 v；默认取 latest）
#   EASYWORK_REPO      仓库（默认 EasyIndie/EasyWork）
#   EASYWORK_BIN_DIR   安装目录（默认 /usr/local/bin 或 ~/.local/bin）
set -euo pipefail

REPO="${EASYWORK_REPO:-EasyIndie/EasyWork}"
VERSION="${EASYWORK_VERSION:-}"
BIN_DIR="${EASYWORK_BIN_DIR:-}"
# 可覆盖为镜像/副本（用于本地验收或 fork）
DOWNLOAD_BASE="${EASYWORK_DOWNLOAD_BASE:-https://github.com/${REPO}/releases/download}"
API_BASE="${EASYWORK_API_BASE:-https://api.github.com}"

log() { printf '  %s\n' "$*"; }
die() {
    printf '  ✗ %s\n' "$*" >&2
    exit 1
}

# ── 检测平台 ────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        MINGW* | MSYS* | CYGWIN*) echo "windows" ;;
        *) die "不支持的操作系统: $(uname -s)" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo "amd64" ;;
        arm64 | aarch64) echo "arm64" ;;
        *) die "不支持的架构: $(uname -m)" ;;
    esac
}

# ── 解析最新版本 ────────────────────────────────────────────
resolve_version() {
    if [[ -n "$VERSION" ]]; then
        echo "${VERSION#v}"
        return 0
    fi
    local api="${API_BASE}/repos/${REPO}/releases/latest"
    local tag
    tag="$(curl -fsSL "$api" 2> /dev/null | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')" || true
    [[ -n "$tag" ]] || die "无法获取最新版本，请设置 EASYWORK_VERSION 后重试"
    echo "${tag#v}"
}

# ── 完整性校验（sha256，缺失时跳过） ────────────────────────
verify_checksum() {
    local base="$1" asset="$2" file="$3"
    local sums="$tmp/checksums.txt"
    if ! curl "${curl_opts[@]}" -o "$sums" "${base}/checksums.txt" 2> /dev/null; then
        log "警告: 未找到 checksums.txt，跳过完整性校验"
        return 0
    fi
    local want
    want="$(awk -v a="$asset" '$2 == a { print $1; exit }' "$sums")"
    if [[ -z "$want" ]]; then
        log "警告: checksums.txt 中无 ${asset}，跳过完整性校验"
        return 0
    fi
    local got=""
    if command -v sha256sum > /dev/null 2>&1; then
        got="$(sha256sum "$file" | awk '{ print $1 }')"
    elif command -v shasum > /dev/null 2>&1; then
        got="$(shasum -a 256 "$file" | awk '{ print $1 }')"
    else
        log "警告: 无 sha256sum/shasum，跳过完整性校验"
        return 0
    fi
    [[ "$got" == "$want" ]] || die "校验失败: ${asset} 的 sha256 不匹配（期望 ${want}，实际 ${got}）"
    log "完整性校验通过 (sha256)"
}

# ── 选择安装目录 ────────────────────────────────────────────
choose_bin_dir() {
    if [[ -n "$BIN_DIR" ]]; then
        echo "$BIN_DIR"
        return 0
    fi
    if [[ -w /usr/local/bin ]]; then
        echo "/usr/local/bin"
    else
        echo "${HOME}/.local/bin"
    fi
}

main() {
    local os arch version url bin_dir asset bin
    os="$(detect_os)"
    arch="$(detect_arch)"
    version="$(resolve_version)"
    bin_dir="$(choose_bin_dir)"
    mkdir -p "$bin_dir"

    asset="easywork_${version}_${os}_${arch}"
    if [[ "$os" == "windows" ]]; then
        url="${DOWNLOAD_BASE}/${version}/${asset}.zip"
        bin="ew.exe"
    else
        url="${DOWNLOAD_BASE}/${version}/${asset}.tar.gz"
        bin="ew"
    fi

    log "EasyWork ${version} (${os}/${arch})"
    log "下载: ${url}"
    # tmp 必须为全局：EXIT trap 在 main 作用域外运行
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    # 默认强制 HTTPS；仅当显式使用 http:// 镜像基址时允许明文 HTTP。
    local curl_opts=(-fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1)
    if [[ "$url" == http://* ]]; then
        log "警告: 使用明文 HTTP 镜像源"
        curl_opts=(-fsSL --proto '=http,https' --retry 3 --retry-delay 1)
    fi
    if ! curl "${curl_opts[@]}" -o "$tmp/archive" "$url"; then
        die "下载失败，请检查网络或版本号"
    fi
    verify_checksum "${DOWNLOAD_BASE}/${version}" "${asset}$([[ "$os" == "windows" ]] && echo .zip || echo .tar.gz)" "$tmp/archive"

    if [[ "$os" == "windows" ]]; then
        if command -v unzip > /dev/null 2>&1; then
            unzip -o -q "$tmp/archive" -d "$tmp" || die "解压失败（unzip）"
        else
            tar -xf "$tmp/archive" -C "$tmp" || die "解压失败（tar）"
        fi
    else
        tar -xzf "$tmp/archive" -C "$tmp" || die "解压失败"
    fi

    local target_name="ew"
    [[ "$os" == "windows" ]] && target_name="ew.exe"
    if ! install -m 0755 "$tmp/${bin}" "${bin_dir}/${target_name}" 2> /dev/null; then
        mkdir -p "$bin_dir"
        cp "$tmp/${bin}" "${bin_dir}/${target_name}"
        chmod +x "${bin_dir}/${target_name}"
    fi
    # 兼容别名 easywork
    if [[ "$os" == "windows" ]]; then
        cp "${bin_dir}/${target_name}" "${bin_dir}/easywork.exe"
    else
        ln -sf ew "${bin_dir}/easywork" 2> /dev/null || true
    fi

    log "已安装: ${bin_dir}/${target_name}"
    if ! echo ":$PATH:" | grep -q ":${bin_dir}:"; then
        log "注意: ${bin_dir} 不在 \$PATH 中，请加入后重试"
    fi
    log "下一步: ew install --yes"
}

main "$@"
