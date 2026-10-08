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

# ─── Internal: install via the detected package manager ───────
_install_gh() {
    local pkg
    pkg="$(detect_pkg_manager)"
    case "$pkg" in
        brew) brew install gh ;;
        apt-get) sudo apt-get update -y && sudo apt-get install -y gh ;;
        dnf) sudo dnf install -y gh ;;
        yum) sudo yum install -y gh ;;
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
