#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# EasyWork — AI coding CLI Module
# Installs pi / codex / claude code via npm (idempotent, offline-aware).

MODULE_NAME="ai-tools"
MODULE_DESCRIPTION="安装 AI 编码 CLI（claude code / codex / pi）"
MODULE_PRIORITY=50

# "<cli>:<npm package>"
_AI_TOOLS=(
    "claude:@anthropic-ai/claude-code"
    "codex:@openai/codex"
    "pi:@earendil-works/pi-coding-agent"
)

module_check() {
    local entry
    for entry in "${_AI_TOOLS[@]}"; do
        has_cmd "${entry%%:*}" && return 0
    done
    return 1
}

module_status() {
    local entry cli found=()
    for entry in "${_AI_TOOLS[@]}"; do
        cli="${entry%%:*}"
        has_cmd "$cli" && found+=("$cli")
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        echo "ai-tools: 已安装 (${found[*]})"
    else
        echo "ai-tools: 未安装"
    fi
}

# ─── Internal: install a single tool via npm ──────────────────
_ai_install() {
    local cli="$1"
    local pkg="$2"

    if ! has_cmd npm; then
        log_warn "未找到 npm，无法自动安装 ${cli}"
        log_info "请先安装 Node.js/npm，或参考官方文档手动安装 ${cli}"
        return 1
    fi

    log_info "npm 安装 ${pkg}..."
    if npm install -g "$pkg" > /dev/null 2>&1; then
        log_success "${cli} 安装完成"
        return 0
    fi
    log_warn "npm 安装 ${pkg} 失败"
    return 1
}

# ─── Module: Install ──────────────────────────────────────────
module_install() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 AI 编码 CLI: claude, codex, pi"
        return 0
    fi

    if [[ "${OFFLINE:-false}" == "true" ]]; then
        log_warn "离线模式：跳过 AI 工具安装"
        return 0
    fi

    if [[ "$(cfg_get_bool ai_tools.install true)" != "true" ]]; then
        log_info "配置已禁用 AI 工具安装（ai_tools.install=false）"
        return 0
    fi

    local entry cli pkg
    local installed=""
    local missing=0
    for entry in "${_AI_TOOLS[@]}"; do
        cli="${entry%%:*}"
        pkg="${entry##*:}"
        if has_cmd "$cli"; then
            log_info "${cli} 已安装"
            installed="${installed}${installed:+,}${cli}"
            continue
        fi
        if _ai_install "$cli" "$pkg"; then
            installed="${installed}${installed:+,}${cli}"
        else
            missing=$((missing + 1))
        fi
    done

    manifest_set_section "ai-tools" \
        "installed=true" \
        "tools=${installed}"

    if [[ "$missing" -gt 0 ]]; then
        log_warn "${missing} 个 AI 工具未能自动安装，请手动安装（见上方提示）"
    fi
    return 0
}

# ─── Module: Uninstall ────────────────────────────────────────
module_uninstall() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将保留已安装的 AI 工具（不自动卸载）"
        return 0
    fi
    # Removing globally-installed CLIs could delete tools the user already had
    # before EasyWork. Keep them; only the manifest entry is removed.
    log_info "保留已安装的 AI 工具（不自动卸载）"
    return 0
}
