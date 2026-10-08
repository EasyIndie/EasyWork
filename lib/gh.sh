#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# EasyWork — GitHub CLI (gh) Module
# Ensures the official GitHub CLI is installed (idempotent, offline-aware).

MODULE_NAME="gh"
MODULE_DESCRIPTION="安装 GitHub CLI (gh)"
MODULE_PRIORITY=25

module_check() { has_cmd gh; }

module_status() {
    if module_check; then
        echo "gh: 已安装 ($(gh --version 2> /dev/null | head -1))"
    else
        echo "gh: 未安装"
    fi
}

# ─── Internal: official repository URLs ──────────────────────
_GH_KEYRING_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
_GH_APT_REPO_URI="https://cli.github.com/packages"
_GH_DNF_REPO_URL="https://cli.github.com/packages/rpm/gh-cli.repo"

# ─── Internal: install via the detected package manager ───────
# Each distro first tries its default repositories; if gh is not available
# there (older Debian/Ubuntu, CentOS, ...), the official GitHub repo is added.
_install_gh() {
    local pkg
    pkg="$(detect_pkg_manager)"
    case "$pkg" in
        brew) brew install gh ;;
        apt-get) _install_gh_apt ;;
        dnf) _install_gh_dnf dnf ;;
        yum) _install_gh_dnf yum ;;
        pacman) sudo pacman -S --noconfirm github-cli ;;
        zypper) sudo zypper install -y gh ;;
        apk) sudo apk add github-cli ;;
        *)
            log_warn "未识别的包管理器，请手动安装 gh"
            log_info "参考: https://cli.github.com/"
            return 1
            ;;
    esac
}

_install_gh_apt() {
    if sudo apt-get update -y > /dev/null 2>&1 && sudo apt-get install -y gh > /dev/null 2>&1; then
        return 0
    fi
    log_info "默认 apt 源未提供 gh，添加 GitHub 官方 apt 源..."
    _setup_gh_apt_repo || return 1
    sudo apt-get install -y gh
}

_setup_gh_apt_repo() {
    local keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    sudo mkdir -p -m 755 /etc/apt/keyrings || return 1

    local tmp
    tmp="$(mktemp)"
    _register_temp_file "$tmp"
    if has_cmd curl; then
        curl -fsSL -o "$tmp" "$_GH_KEYRING_URL" || return 1
    elif has_cmd wget; then
        wget -qO "$tmp" "$_GH_KEYRING_URL" || return 1
    else
        log_warn "需要 curl 或 wget 才能添加 GitHub 官方源"
        return 1
    fi
    sudo cp "$tmp" "$keyring" || return 1
    sudo chmod go+r "$keyring" || true

    local arch
    arch="$(dpkg --print-architecture 2> /dev/null || echo amd64)"
    printf 'deb [arch=%s signed-by=%s] %s stable main\n' "$arch" "$keyring" "$_GH_APT_REPO_URI" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null || return 1
    sudo apt-get update -y > /dev/null 2>&1 || true
    return 0
}

_install_gh_dnf() {
    local mgr="$1"
    if sudo "$mgr" install -y gh > /dev/null 2>&1; then
        return 0
    fi
    log_info "默认 ${mgr} 源未提供 gh，添加 GitHub 官方 dnf 源..."
    _setup_gh_dnf_repo "$mgr" || return 1
    sudo "$mgr" install -y gh --repo gh-cli
}

_setup_gh_dnf_repo() {
    local mgr="$1"
    sudo "$mgr" install -y 'dnf-command(config-manager)' > /dev/null 2>&1 || true
    # dnf4/yum syntax, then dnf5 syntax
    if sudo "$mgr" config-manager --add-repo "$_GH_DNF_REPO_URL" > /dev/null 2>&1; then
        return 0
    fi
    sudo "$mgr" config-manager addrepo --from-repofile="$_GH_DNF_REPO_URL" > /dev/null 2>&1
}

# ─── Module: Install ──────────────────────────────────────────
module_install() {
    if has_cmd gh; then
        log_info "gh 已安装: $(gh --version 2> /dev/null | head -1)"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 GitHub CLI (gh)"
        return 0
    fi

    if [[ "${OFFLINE:-false}" == "true" ]]; then
        log_warn "离线模式：跳过 gh 安装"
        return 0
    fi

    log_info "安装 GitHub CLI (gh)..."
    if ! _install_gh; then
        log_error "gh 安装失败，可手动安装: https://cli.github.com/"
        return $EXIT_ERROR
    fi

    if has_cmd gh; then
        log_success "gh 安装完成: $(gh --version 2> /dev/null | head -1)"
    else
        log_warn "gh 安装后仍未在 PATH 中找到，请检查 PATH"
    fi
    return 0
}

# ─── Module: Uninstall ────────────────────────────────────────
module_uninstall() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将保留已安装的 gh（不自动卸载）"
        return 0
    fi
    log_info "保留已安装的 gh（不自动卸载）"
    return 0
}
