#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# EasyWork — Shell Configuration Module
# Configures zsh/bash environment with prompt, aliases, and utility functions.

MODULE_NAME="shell"
MODULE_DESCRIPTION="配置 Shell 环境 (bash/zsh 适配)"
MODULE_PRIORITY=10

SH_CONFIG_FILE="$HOME/.sh_config_custom"

module_check() {
    [[ -f "$SH_CONFIG_FILE" ]] && grep -qF "EasyWork managed section" "$SH_CONFIG_FILE" 2> /dev/null
}

module_status() {
    if module_check; then
        local shell_type
        shell_type="$(manifest_read 'shell_type' 'bash/zsh')"
        echo "shell: 已安装 (${shell_type}) — ${SH_CONFIG_FILE}"
    else
        echo "shell: 未安装"
    fi
}

# ─── Internal: detect shell rc file ───────────────────────────
_detect_shell_rc() {
    local os_type
    os_type="$(detect_os)"
    local sh_type
    sh_type="$(detect_shell)"

    # zsh always uses .zshrc regardless of OS
    if [[ "$sh_type" == "zsh" ]]; then
        echo "$HOME/.zshrc"
        return
    fi

    case "$os_type" in
        macos)
            case "$sh_type" in
                bash) echo "$HOME/.bash_profile" ;;
                *) echo "$HOME/.bashrc" ;;
            esac
            ;;
        *)
            echo "$HOME/.bashrc"
            ;;
    esac
}

# ─── Internal: install Oh My Zsh ──────────────────────────────
_install_ohmyzsh() {
    local sh_type
    sh_type="$(detect_shell)"
    local os_type
    os_type="$(detect_os)"

    if [[ "$sh_type" != "zsh" ]]; then
        return 0
    fi

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Oh My Zsh 已安装"
        return 0
    fi

    log_info "安装 Oh My Zsh..."
    RUNZSH="no" KEEP_ZSHRC="yes" CHSH="no" \
        sh -c "$(safe_download 'https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh')" 2> /dev/null || {
        log_warn "Oh My Zsh 安装失败，将跳过（不影响其他配置）"
        return 0
    }
    log_success "Oh My Zsh 安装完成"
}

# ─── Internal: generate shell config content ──────────────────
_generate_shell_config() {
    cat << 'SHELLCONF'

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# enable bracketed paste mode
if [ -n "${BASH_VERSION:-}" ]; then
    bind 'set enable-bracketed-paste on' 2>/dev/null || true
fi

# ── Color Variables ──
BLACK=$'\e[30m'
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
PURPLE=$'\e[35m'
CYAN=$'\e[36m'
WHITE=$'\e[37m'
RESET=$'\e[0m'

export CLICOLOR=1
SHELLCONF

    # ── Fancy prompt (opt-in) ──
    if [[ "$(cfg_get_bool shell.enable_fancy_prompt false)" == "true" ]]; then
        cat << 'SHELLCONF'

# ── Git Prompt Helpers ──
git-branch-name() {
    git symbolic-ref --short -q HEAD 2>/dev/null
}

git-branch-prompt() {
    local branch; branch="$(git-branch-name)"
    if [ "$branch" ]; then
        local hint; hint="$(git branch --format '%(refname:short) -> %(upstream:short)' 2>/dev/null | grep "^${branch} -> " || true)"
        printf "[%s]" "$hint"
    fi
}

# ── Prompt ──
if [ -n "${ZSH_VERSION:-}" ]; then
    setopt PROMPT_SUBST
    PROMPT=$'\n{\\__/}\n(● .●)\n/ >>> %{${CYAN}%}%n@%m:%d%{${RESET}%} %{${GREEN}%}$(git-branch-prompt)%{${RESET}%}'$'\n$ '
else
    PS1='\n{\\__/}\n(● .●)\n/ >>> \[${CYAN}\]\u@\h:\w\[${RESET}\] \[${GREEN}\]$(git-branch-prompt)\[${RESET}\]\n\$ '
fi

SHELLCONF
    fi

    # ── Aliases (default on) ──
    if [[ "$(cfg_get_bool shell.enable_aliases true)" == "true" ]]; then
        cat << 'SHELLCONF'

# ── System Aliases ──
alias grep='grep --color=auto'
alias mv='mv -i'
alias cp='cp -i'
alias rm='rm -i'
alias q='exit'

# ── Git Shorthand ──
alias g='git'

# ── FFmpeg Shorthands ──
alias ff='ffmpeg'
alias fp='ffplay'
alias fb='ffprobe'
alias fs='ffserver'

# ── Swift Package Manager ──
alias spm='swift package'
SHELLCONF
    fi

    # ── Utility: Repeat command N times ──
    cat << 'SHELLCONF'
run() {
    local number="$1"
    shift
    for ((n = 0; n < number; n++)); do "$@"; done
}
SHELLCONF

    # ── macOS network/VPN tools (opt-in) ──
    if [[ "$(cfg_get_bool shell.enable_net_tools false)" == "true" ]]; then
        cat << 'SHELLCONF'

# ── Utility: Flush DNS cache (macOS) ──
flushdns() {
    sudo dscacheutil -flushcache 2>/dev/null; sudo killall -HUP mDNSResponder 2>/dev/null
}

# ── Network Service Helpers (macOS) ──
_require_name() {
    if [ -z "${1:-}" ]; then
        echo "Missing service name" >&2
        return 1
    fi
}

net_list() {
    networksetup -listallnetworkservices 2>/dev/null || echo "networksetup not available"
}

net_enable() {
    _require_name "$1" || return 1
    networksetup -setnetworkserviceenabled "$1" on
}

net_disable() {
    _require_name "$1" || return 1
    networksetup -setnetworkserviceenabled "$1" off
}

net_stat() {
    _require_name "$1" || return 1
    networksetup -getnetworkserviceenabled "$1"
}

# ── VPN Helpers (macOS) ──
vpn_list() {
    scutil --nc list 2>/dev/null || echo "scutil not available"
}

vpn_start() {
    _require_name "$1" || return 1
    scutil --nc start "$1"
}

vpn_stop() {
    _require_name "$1" || return 1
    scutil --nc stop "$1"
}

vpn_stat() {
    _require_name "$1" || return 1
    scutil --nc status "$1"
}

vpn() {
    vpn_stat "$1"
}

vpn_restart() {
    _require_name "$1" || return 1
    vpn_stop "$1" && sleep 1 && vpn_start "$1"
}

# ── System Info ──
sys_info() {
    system_profiler SPHardwareDataType SPSoftwareDataType 2>/dev/null || echo "Only available on macOS"
}
SHELLCONF
    fi
}

# ─── Module: Install ──────────────────────────────────────────
module_install() {
    local os_type
    os_type="$(detect_os)"
    local sh_type
    sh_type="$(detect_shell)"
    local rc_file
    rc_file="$(_detect_shell_rc)"

    log_info "系统: $os_type, Shell: $sh_type"
    log_info "Shell 配置文件: $rc_file"

    # Install Oh My Zsh on zsh, only when explicitly enabled (opt-in)
    # Note: CHSH=no prevents automatic default shell switch, safe for all platforms
    if [[ "$sh_type" == "zsh" ]] && [[ "$(cfg_get_bool shell.enable_ohmyzsh false)" == "true" ]]; then
        _install_ohmyzsh
    fi

    # Ensure rc file exists
    if [[ ! -f "$rc_file" ]]; then
        touch "$rc_file"
        log_info "已创建: $rc_file"
    fi

    # Generate shell config with managed section
    local config_content
    config_content="$(_generate_shell_config)"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将写入 Shell 配置到: $SH_CONFIG_FILE"
        log_info "[DRY-RUN] 将在 $rc_file 中注入 source 行"
        return 0
    fi

    replace_managed_section "$SH_CONFIG_FILE" "$EASYWORK_VERSION" "$config_content"
    log_success "已生成: $SH_CONFIG_FILE"

    # Inject source line into rc file
    local source_line="source $SH_CONFIG_FILE  # EasyWork shell config"
    if ! grep -qF "source $SH_CONFIG_FILE" "$rc_file" 2> /dev/null; then
        echo "" >> "$rc_file"
        echo "$source_line" >> "$rc_file"
        log_success "已注入 source 至: $rc_file"
    else
        log_info "source 行已存在，跳过注入"
    fi

    # Record to manifest
    manifest_set_section "shell" \
        "installed=true" \
        "shell_type=${sh_type}" \
        "display_name=shell (${sh_type})" \
        "source_file=${rc_file}" \
        "config_created=${SH_CONFIG_FILE}"

    # Note: config takes effect automatically in new shell sessions
    log_info "配置将在新终端会话中自动生效"
    return 0
}

# ─── Module: Uninstall ────────────────────────────────────────
module_uninstall() {
    local rc_file
    rc_file="$(_detect_shell_rc)"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将从 $rc_file 移除 source 行"
        log_info "[DRY-RUN] 将删除 $SH_CONFIG_FILE"
        return 0
    fi

    # Remove source line from rc file
    if [[ -f "$rc_file" ]]; then
        local tmpfile
        tmpfile="${rc_file}.tmp.$$"
        grep -vF "source $SH_CONFIG_FILE  # EasyWork" "$rc_file" > "$tmpfile" 2> /dev/null || true
        mv "$tmpfile" "$rc_file"
        log_success "已从 $rc_file 移除 source 行"
    fi

    # Remove shell config file
    if [[ -f "$SH_CONFIG_FILE" ]]; then
        local answer="y"
        if [[ "${YES_MODE:-false}" != "true" ]]; then
            read -r -p "  删除 $SH_CONFIG_FILE？[Y/n] " answer
        fi
        if [[ ! "$answer" =~ ^[Nn] ]]; then
            rm -f "$SH_CONFIG_FILE"
            log_success "已删除: $SH_CONFIG_FILE"
        else
            log_info "保留: $SH_CONFIG_FILE"
        fi
    fi

    return 0
}
