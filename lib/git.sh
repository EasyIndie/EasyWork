#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# EasyWork — Git Configuration Module
# Configures Git user identity and extensive alias set.

MODULE_NAME="git"
MODULE_DESCRIPTION="配置 Git 别名和身份"
MODULE_PRIORITY=20

GIT_CONFIG_FILE="$HOME/.gitconfig"

# Declarative file target for the engine (applied on global-scope install)
MODULE_DECLARE=(
    "$GIT_CONFIG_FILE|_generate_git_config_resolved|#|config_backup"
)

module_check() {
    [[ -f "$GIT_CONFIG_FILE" ]] && grep -qF "EasyWork managed section" "$GIT_CONFIG_FILE" 2> /dev/null
}

module_status() {
    if module_check; then
        local name
        name="$(git config --global user.name 2> /dev/null || echo 'unknown')"
        local email
        email="$(git config --global user.email 2> /dev/null || echo 'unknown')"
        echo "git: 已安装 — ${name} <${email}>"
    else
        echo "git: 未安装"
    fi
}

# ─── Input Validation ─────────────────────────────────────────
_validate_email() {
    local email="$1"
    # Basic email format validation
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

_validate_name() {
    local name="$1"
    # Must not be empty
    [[ -n "$name" ]] || return 1
    # Must not contain dangerous shell metacharacters
    local pattern
    pattern='[$`\|&;(){}<>!#~]'
    if echo "$name" | grep -qE "$pattern" 2> /dev/null; then
        return 1
    fi
    return 0
}

# ─── Show Git Config ──────────────────────────────────────────
_show_current_git_config() {
    local scope="${1:-global}"
    local name
    name="$(git config --"$scope" user.name 2> /dev/null || echo '(未设置)')"
    local email
    email="$(git config --"$scope" user.email 2> /dev/null || echo '(未设置)')"
    echo "  Git 用户名: $name"
    echo "  Git 邮箱:   $email"
}

# ─── Select Scope ──────────────────────────────────────────────
_select_scope() {
    echo ""
    echo "  选择配置级别:"
    echo "    1) global — 用户级（~/.gitconfig），所有仓库生效"
    echo "    2) local  — 仓库级（当前仓库 .git/config）"

    local choice
    if [[ "${YES_MODE:-false}" != "true" ]]; then
        read -r -p "  请选择 [1-2]: " choice
    else
        choice="1"
        log_info "非交互模式，使用默认: global"
    fi

    case "$choice" in
        1) GIT_SCOPE="global" ;;
        2)
            if ! git rev-parse --git-dir > /dev/null 2>&1; then
                log_error "当前目录不在 Git 仓库中，无法使用 local 级别"
                return 1
            fi
            GIT_SCOPE="local"
            GIT_CONFIG_FILE="$(git rev-parse --show-toplevel)/.git/config"
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    log_info "配置级别: ${GIT_SCOPE}"
    return 0
}

# ─── Internal: identity usability check ───────────────────────
# 判断 name/email 是否为可用身份（非空、非模板占位、格式合法）
_identity_usable() {
    local name="${1:-}"
    local email="${2:-}"
    [[ -n "$name" ]] || return 1
    [[ "$name" != "Your Name" ]] || return 1
    [[ -n "$email" ]] || return 1
    [[ "$email" != your@* ]] || return 1
    _validate_name "$name" || return 1
    _validate_email "$email" || return 1
    return 0
}

# ─── Internal: non-interactive identity auto-detection ────────
# 探测顺序：config personal → config work → 已有 git 全局身份 → 跳过。
# 任何情况下都不阻塞安装；dry-run 时用占位值预览。
_select_identity_auto() {
    # 1. 配置文件中第一个可用身份
    if _identity_usable "${GIT_PERSONAL_NAME:-}" "${GIT_PERSONAL_EMAIL:-}"; then
        GIT_USER_NAME="$GIT_PERSONAL_NAME"
        GIT_USER_EMAIL="$GIT_PERSONAL_EMAIL"
        log_info "使用身份 (personal): ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
        return 0
    fi
    if _identity_usable "${GIT_WORK_NAME:-}" "${GIT_WORK_EMAIL:-}"; then
        GIT_USER_NAME="$GIT_WORK_NAME"
        GIT_USER_EMAIL="$GIT_WORK_EMAIL"
        log_info "使用身份 (work): ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
        return 0
    fi

    # 2. 复用已有的 git 全局身份（不打断用户）
    local existing_name existing_email
    existing_name="$(git config --global user.name 2> /dev/null || true)"
    existing_email="$(git config --global user.email 2> /dev/null || true)"
    if _identity_usable "$existing_name" "$existing_email"; then
        GIT_USER_NAME="$existing_name"
        GIT_USER_EMAIL="$existing_email"
        log_info "复用已有 Git 身份: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
        return 0
    fi

    # 3. dry-run：用占位值预览，保持输出可读
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        GIT_USER_NAME="your-name"
        GIT_USER_EMAIL="your@email.com"
        log_info "[DRY-RUN] 未检测到身份，使用占位值预览"
        return 0
    fi

    # 4. 都没有：跳过身份配置，只装别名，不阻塞
    GIT_USER_NAME=""
    GIT_USER_EMAIL=""
    log_warn "未检测到 Git 身份，跳过身份配置（仅配置别名）"
    log_info "稍后设置身份: easywork config edit && easywork install git"
    return 0
}

# ─── Select Identity ───────────────────────────────────────────
_select_identity() {
    # Load config for available identities
    config_load

    # 非交互模式：自动探测，绝不阻塞
    if [[ "${YES_MODE:-false}" == "true" ]]; then
        _select_identity_auto
        return $?
    fi

    echo ""
    echo "  选择 Git 身份:"
    echo "    1) personal  — ${GIT_PERSONAL_NAME:-'(未配置)'} <${GIT_PERSONAL_EMAIL:-'(未配置)'}>"
    echo "    2) work      — ${GIT_WORK_NAME:-'(未配置)'} <${GIT_WORK_EMAIL:-'(未配置)'}>"
    echo "    3) custom    — 手动输入"

    local choice identity_type
    read -r -p "  请选择 [1-3]: " choice

    case "$choice" in
        1)
            GIT_USER_NAME="${GIT_PERSONAL_NAME:-}"
            GIT_USER_EMAIL="${GIT_PERSONAL_EMAIL:-}"
            identity_type="personal"
            ;;
        2)
            GIT_USER_NAME="${GIT_WORK_NAME:-}"
            GIT_USER_EMAIL="${GIT_WORK_EMAIL:-}"
            identity_type="work"
            ;;
        3)
            read -r -p "  输入 Git 用户名: " GIT_USER_NAME
            read -r -p "  输入 Git 邮箱: " GIT_USER_EMAIL
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    # Detect placeholder / empty values — guide user to input real ones
    local name_is_placeholder=false
    local email_is_placeholder=false

    if [[ "${GIT_USER_NAME:-}" == "Your Name" ]] || [[ -z "${GIT_USER_NAME:-}" ]]; then
        name_is_placeholder=true
    fi
    if [[ "${GIT_USER_EMAIL:-}" =~ ^your@ ]] || [[ -z "${GIT_USER_EMAIL:-}" ]]; then
        email_is_placeholder=true
    fi

    if $name_is_placeholder || $email_is_placeholder; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            # Dry-run: use dummy values for preview
            $name_is_placeholder && GIT_USER_NAME="your-name"
            $email_is_placeholder && GIT_USER_EMAIL="your@email.com"
        else
            log_warn "尚未配置 Git 身份信息"
            echo ""
            log_info "输入 Git 用户名和邮箱，或直接回车跳过 Git 配置"
            echo ""

            local skipped=false

            if $name_is_placeholder; then
                local input_name=""
                while true; do
                    read -r -p "  Git 用户名 (回车跳过): " input_name
                    if [[ -z "$input_name" ]]; then
                        log_info "已跳过 Git 配置"
                        GIT_USER_NAME=""
                        GIT_USER_EMAIL=""
                        return 0
                    fi
                    if _validate_name "$input_name"; then
                        GIT_USER_NAME="$input_name"
                        break
                    fi
                    log_warn "用户名不能为空或包含特殊字符，请重新输入"
                done
            fi

            if $email_is_placeholder; then
                local input_email=""
                while true; do
                    read -r -p "  Git 邮箱 (回车跳过): " input_email
                    if [[ -z "$input_email" ]]; then
                        log_info "已跳过 Git 配置"
                        GIT_USER_NAME=""
                        GIT_USER_EMAIL=""
                        return 0
                    fi
                    if _validate_email "$input_email"; then
                        GIT_USER_EMAIL="$input_email"
                        break
                    fi
                    log_warn "邮箱格式无效，请重新输入"
                done
            fi

            echo ""
            log_success "已记录 Git 身份: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"

            # Save to config file for future use
            if [[ "$identity_type" == "personal" ]]; then
                local save_config="y"
                read -r -p "  保存到配置文件以便下次使用？[Y/n] " save_config
                if [[ ! "$save_config" =~ ^[Nn] ]]; then
                    $name_is_placeholder && cfg_set "git.identities.personal.name" "$GIT_USER_NAME"
                    $email_is_placeholder && cfg_set "git.identities.personal.email" "$GIT_USER_EMAIL"
                    log_info "已保存到 $(config_path)"
                fi
            elif [[ "$identity_type" == "work" ]]; then
                local save_config="y"
                read -r -p "  保存到配置文件以便下次使用？[Y/n] " save_config
                if [[ ! "$save_config" =~ ^[Nn] ]]; then
                    $name_is_placeholder && cfg_set "git.identities.work.name" "$GIT_USER_NAME"
                    $email_is_placeholder && cfg_set "git.identities.work.email" "$GIT_USER_EMAIL"
                    log_info "已保存到 $(config_path)"
                fi
            fi
        fi
    fi

    # Validate
    if ! _validate_name "${GIT_USER_NAME:-}"; then
        log_error "Git 用户名无效或为空。请编辑 $(config_path)"
        return 1
    fi
    if ! _validate_email "${GIT_USER_EMAIL:-}"; then
        log_error "Git 邮箱格式无效: ${GIT_USER_EMAIL:-}"
        log_error "请编辑 $(config_path) 填入正确的邮箱地址"
        return 1
    fi

    log_info "使用身份: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
    return 0
}

# ─── Generate Git Config ──────────────────────────────────────
_generate_git_config() {
    cat << 'GITCONF'
[diff]
    submodule = log

[pager]
    branch = false

[pull]
    rebase = false

[color]
    ui = auto

[alias]
    # ── Config ──
    cfg = config --global --list
    cfl = config --local --list
    cfs = config --system --list
    cfw = config --worktree --list

    # ── Log (美化日志) ──
    l = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(bold yellow) by %an' --abbrev-commit --date=relative --decorate
    la = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(bold yellow) by %an' --abbrev-commit --date=relative --decorate --all
    lm = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative --decorate --author="$(git config user.name)"
    lma = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative --decorate --author="$(git config user.name)" --all
    lc = log --oneline -n 10
    lg = log --graph --oneline --decorate --all
    lgs = log --stat -n 1
    lgt = log --oneline --since="2 weeks ago"
    lgb = log --oneline --branches
    lgr = log --oneline --remotes
    lgtg = log --oneline --tags

    # ── Branch ──
    b = branch
    br = branch -r
    bv = branch -vv
    bd = branch -d
    bD = branch -D
    bu = branch -u

    # ── Pull / Push ──
    pl = pull
    plrs = pull --recurse-submodules --ff-only
    plrb = pull --rebase
    pu = push
    pm = push --mirror
    po = push origin
    pof = push origin -f
    poh = push origin HEAD
    pot = push origin --tags
    poa = push origin --all
    pofs = push origin --force-with-lease

    # ── Add / Commit ──
    a = add
    c = commit
    ca = commit --amend
    cm = commit -m

    # ── Checkout ──
    co = checkout
    cb = checkout -b

    # ── Clone ──
    cl = clone
    cdf = clean -dxf
    clrs = clone --recurse-submodules

    # ── Cherry Pick ──
    pk = cherry-pick
    pkc = cherry-pick --continue
    pka = cherry-pick --abort

    # ── Diff ──
    d = diff
    dsm = diff --submodule

    # ── Merge ──
    m = merge
    mc = merge --continue
    ma = merge --abort

    # ── Status ──
    s = status
    ss = status -s

    # ── Stash ──
    st = stash
    sl = stash list
    sp = stash pop

    # ── Tag ──
    t = tag
    tl = tag -l
    td = tag -d

    # ── Submodule ──
    sm = submodule
    smi = submodule init
    smu = submodule update
    sms = submodule sync
    smur = submodule update --remote
    smuir = submodule update --init --recursive

    # ── Remote ──
    r = remote
    ra = remote add
    rv = remote -v
    rp = remote prune
    rpo = remote prune origin

    # ── Restore / Reset / Revert ──
    dp = restore
    re = restore
    ic = update-index --assume-unchanged
    uic = update-index --no-assume-unchanged
    rst = reset
    rsth = reset --hard HEAD
    rvt = revert

    # ── Rebase ──
    rb = rebase
    rbc = rebase --continue
    rba = rebase --abort
    rbi = rebase -i
    rbir = rebase -i --root

    # ── Worktree ──
    wt = worktree
    wta = worktree add
    wtl = worktree list
    wtr = worktree remove
    wtm = worktree move
    wtp = worktree prune

    # ── Format Patch ──
    fp = format-patch
    fp1 = format-patch -1
    ap = am

    # ── Misc ──
    h = config --global --list
    sh = !git --no-pager show HEAD
GITCONF
}

# Resolve identity (content_fn contract for the engine).
# When no identity is configured, only the alias set is emitted.
_generate_git_config_resolved() {
    local content
    content="$(_generate_git_config)"
    if [[ -n "${GIT_USER_NAME:-}" ]] && [[ -n "${GIT_USER_EMAIL:-}" ]]; then
        printf '[user]\n    name = %s\n    email = %s\n\n%s' \
            "$GIT_USER_NAME" "$GIT_USER_EMAIL" "$content"
    else
        printf '%s' "$content"
    fi
}

# ─── Module: Install ──────────────────────────────────────────
module_install() {
    if ! has_cmd git; then
        log_error "Git 未安装"
        return $EXIT_MISSING_DEPS
    fi

    # Ensure config is loaded
    if ! config_exists; then
        config_init
    fi
    config_load

    # Select scope (global vs local repo)
    if ! _select_scope; then
        return $EXIT_ERROR
    fi

    # Select identity
    if ! _select_identity; then
        return $EXIT_ERROR
    fi

    # No identity detected: local scope has nothing to write, so skip.
    # Global scope still installs the alias set (identity-less).
    if [[ -z "${GIT_USER_NAME:-}" ]] && [[ "$GIT_SCOPE" == "local" ]]; then
        log_info "已跳过 Git 配置"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        if [[ -n "${GIT_USER_NAME:-}" ]]; then
            log_info "[DRY-RUN] 将配置 Git 身份 (${GIT_SCOPE}): ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
        else
            log_info "[DRY-RUN] 将安装 Git 别名（未配置身份）"
        fi
        return 0
    fi

    if [[ "$GIT_SCOPE" == "local" ]]; then
        # ——— Local repo config: use git config --local ———
        git config --local user.name "$GIT_USER_NAME"
        git config --local user.email "$GIT_USER_EMAIL"
        log_success "已设置仓库级 Git 身份: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"

        manifest_set_section "git" \
            "installed=true" \
            "scope=local" \
            "repo=$(git rev-parse --show-toplevel)"
    else
        # ——— Global config: managed section with aliases ———
        local config_backup=""
        apply_module_files || return $EXIT_ERROR
        if [[ -n "$config_backup" ]]; then
            log_info "已备份现有 ~/.gitconfig → ${config_backup}"
        fi
        log_success "已生成: $GIT_CONFIG_FILE"

        manifest_set_section "git" \
            "installed=true" \
            "scope=global" \
            "config_file=${GIT_CONFIG_FILE}" \
            "${config_backup:+config_backup=${config_backup}}"
    fi

    log_success "Git 配置完成 ✓"
    _show_current_git_config "$GIT_SCOPE"

    return 0
}

# ─── Module: Uninstall ────────────────────────────────────────
module_uninstall() {
    local scope
    scope="$(manifest_read_section_key 'git' 'scope')"
    scope="${scope:-global}"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将移除 Git 配置 (${scope})"
        return 0
    fi

    if [[ "$scope" == "local" ]]; then
        # ——— Local repo config: git config --local --unset ———
        local repo
        repo="$(manifest_read_section_key 'git' 'repo')"
        if [[ -n "$repo" ]] && [[ -d "$repo/.git" ]]; then
            git -C "$repo" config --local --unset user.name 2> /dev/null || true
            git -C "$repo" config --local --unset user.email 2> /dev/null || true
            log_success "已移除仓库级 Git 身份"
        else
            log_warn "仓库目录不存在，跳过"
        fi
        return 0
    fi

    # ——— Global config uninstall ———
    local config_backup
    config_backup="$(manifest_read_section_key 'git' 'config_backup' '')"
    if [[ -n "$config_backup" ]] && [[ -f "$config_backup" ]]; then
        local answer="y"
        if [[ "${YES_MODE:-false}" != "true" ]]; then
            read -r -p "  恢复备份的 ~/.gitconfig？[Y/n] " answer
        fi
        if [[ ! "$answer" =~ ^[Nn] ]]; then
            remove_managed_file "$GIT_CONFIG_FILE" "$config_backup"
            log_success "已恢复备份的 ~/.gitconfig"
        fi
    else
        if [[ -f "$GIT_CONFIG_FILE" ]] && grep -qF "EasyWork managed section" "$GIT_CONFIG_FILE" 2> /dev/null; then
            local answer="y"
            if [[ "${YES_MODE:-false}" != "true" ]]; then
                read -r -p "  移除 EasyWork 写入的 Git 配置？[Y/n] " answer
            fi
            if [[ ! "$answer" =~ ^[Nn] ]]; then
                remove_managed_file "$GIT_CONFIG_FILE" ""
                log_success "已移除 EasyWork Git 配置"
            fi
        fi
    fi

    return 0
}
