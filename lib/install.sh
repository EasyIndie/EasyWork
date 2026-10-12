#!/usr/bin/env bash
# EasyWork — Install & Uninstall Orchestration
# Provides: cmd_install, cmd_uninstall, _finalize_uninstall
# Sourced by bin/easywork after common.sh and completions.sh.

# ─── CLI: Install ─────────────────────────────────────────────
cmd_install() {
    local targets=("$@")

    # Validate target modules if specified
    if [[ ${#targets[@]} -gt 0 ]]; then
        _discover_modules "$LIB_DIR"
        local t
        for t in "${targets[@]}"; do
            if ! module_registered "$t"; then
                log_error "未知组件: $t"
                if [[ "${JSON_MODE:-false}" != "true" ]]; then echo ""; fi
                log_info "可用组件:"
                list_modules
                return $EXIT_ERROR
            fi
        done
    fi

    echo ""
    local channel_label="${EASYWORK_CHANNEL:+ (${EASYWORK_CHANNEL})}"
    printf "  %sEasyWork %s%s%s%s — 开发环境配置%s\n" "${C_CYAN}" "${C_RESET}" "${EASYWORK_VERSION}" "${channel_label}" "${C_CYAN}" "${C_RESET}"
    echo ""

    # Preflight check
    if ! preflight_check; then
        return $?
    fi

    acquire_lock || return $?

    # Detect old installation (from previous scripts/ era)
    if [[ -f "$HOME/.sh_config_custom" ]]; then
        if ! grep -qF "# >>> EasyWork managed section" "$HOME/.sh_config_custom" 2> /dev/null; then
            log_warn "检测到旧版 EasyWork 配置（无版本管理）"
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                log_info "[DRY-RUN] 将备份旧配置并迁移"
            elif [[ "${YES_MODE:-false}" != "true" ]]; then
                local answer
                read -r -p "  是否迁移到新版本？旧配置将备份后替换。[Y/n] " answer
                if [[ "$answer" =~ ^[Nn] ]]; then
                    log_info "跳过 Shell 配置迁移，其他组件正常安装"
                else
                    backup_file "$HOME/.sh_config_custom"
                    log_info "已备份旧配置"
                fi
            else
                backup_file "$HOME/.sh_config_custom"
            fi
        fi
    fi

    # Determine install mode
    local install_mode="fresh"
    local _run_modules=true
    if manifest_exists; then
        local installed_ver
        installed_ver="$(manifest_get_version)" || installed_ver="0.0.0"
        if [[ "$installed_ver" == "$EASYWORK_VERSION" ]]; then
            install_mode="same_version"
        elif _semver_is_newer "$EASYWORK_VERSION" "$installed_ver"; then
            install_mode="upgrade"
        else
            log_warn "已安装版本 (${installed_ver}) 高于当前 (${EASYWORK_VERSION})，可能是降级"
            install_mode="downgrade"
        fi
    fi

    case "$install_mode" in
        fresh)
            log_info "全新安装 EasyWork ${EASYWORK_VERSION}${EASYWORK_CHANNEL:+ (${EASYWORK_CHANNEL})}"
            config_init
            manifest_init "$EASYWORK_VERSION"
            ;;
        upgrade)
            log_info "升级: ${installed_ver} → ${EASYWORK_VERSION}${EASYWORK_CHANNEL:+ (${EASYWORK_CHANNEL})}"
            ;;
        same_version)
            log_info "已安装 ${EASYWORK_VERSION}${EASYWORK_CHANNEL:+ (${EASYWORK_CHANNEL})}，配置已是最新"
            if $IS_PIPED; then
                :
            elif [[ ${#targets[@]} -gt 0 ]]; then
                :
            elif [[ "${YES_MODE:-false}" != "true" ]]; then
                local answer
                read -r -p "  重新应用配置？[y/N] " answer
                if [[ ! "$answer" =~ ^[Yy] ]]; then
                    _run_modules=false
                fi
            else
                _run_modules=false
            fi
            if $_run_modules; then
                log_info "刷新配置..."
            fi
            ;;
    esac

    # Run all modules (skip in piped mode — CLI binary only)
    if ! $IS_PIPED && $_run_modules; then
        local sorted
        sorted="$(list_modules_sorted)" || {
            log_error "无法获取模块列表"
            release_lock
            return $EXIT_ERROR
        }

        local failed_modules=()
        for name in $sorted; do
            # Filter by targets if specified
            if [[ ${#targets[@]} -gt 0 ]]; then
                local matched=false t
                for t in "${targets[@]}"; do
                    [[ "$name" == "$t" ]] && matched=true
                done
                $matched || continue
            fi
            echo ""
            log_info "配置 ${name}..."
            # Re-source module file so the correct module_install is in scope
            if [[ -f "${LIB_DIR}/${name}.sh" ]]; then
                source "${LIB_DIR}/${name}.sh"
            fi
            if module_install; then
                # Modules that self-record (git/vim/gh/ai-tools) must keep their
                # own keys; only fall back to a bare section when absent.
                if ! manifest_section_exists "$name"; then
                    manifest_set_section "$name" \
                        "installed=true"
                fi
                log_success "${name} 完成"
            else
                log_error "[${name}] 失败"
                failed_modules+=("$name")
                manifest_set_section "$name" \
                    "installed=failed" \
                    "failed_at=$(date +%Y-%m-%dT%H:%M:%S%z)"
            fi
        done

        if [[ ${#failed_modules[@]} -gt 0 ]]; then
            echo ""
            log_warn "以下组件安装失败: ${failed_modules[*]}"
            log_warn "你可以修复问题后重新运行: easywork install ${failed_modules[*]}"
            log_verbose "失败信息已记录在 manifest 中，可运行 easywork version 查看状态"
        fi
    fi

    # Update manifest version
    if manifest_exists; then
        local manifest_tmp
        manifest_tmp="$(mktemp)" || {
            log_error "无法创建临时文件 (mktemp 失败)"
            release_lock
            return $EXIT_ERROR
        }
        _register_temp_file "$manifest_tmp"
        sed "s/^easywork_version=.*/easywork_version=${EASYWORK_VERSION}/" "$MANIFEST_FILE" > "$manifest_tmp"
        mv "$manifest_tmp" "$MANIFEST_FILE"
    fi

    echo ""
    if $IS_PIPED; then
        local channel_label="${EASYWORK_CHANNEL:+ (${EASYWORK_CHANNEL})}"
        log_success "EasyWork ${EASYWORK_VERSION}${channel_label} CLI 准备就绪"
    else
        local channel_label="${EASYWORK_CHANNEL:+ (${EASYWORK_CHANNEL})}"
        log_success "EasyWork ${EASYWORK_VERSION}${channel_label} 安装完成 🎉"
        log_info "运行 easywork 查看可用命令"
    fi

    # Self-install: always overwrite binary when piped
    if $IS_PIPED; then
        echo ""
        log_info "安装 easywork 到系统路径..."
        local install_path
        # 支持 EASYWORK_BIN_DIR 覆盖安装目录（与 bootstrap.sh 一致；
        # 测试/CI 借此避免误写系统路径 /usr/local/bin）。
        if [[ -n "${EASYWORK_BIN_DIR:-}" ]]; then
            mkdir -p "$EASYWORK_BIN_DIR" 2> /dev/null || true
            install_path="${EASYWORK_BIN_DIR%/}/easywork"
        elif [[ -w "/usr/local/bin" ]]; then
            install_path="/usr/local/bin/easywork"
        elif [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2> /dev/null; then
            install_path="$HOME/.local/bin/easywork"
        fi
        if [[ -n "${install_path:-}" ]]; then
            if safe_download "${EASYWORK_RAW_URL}/bin/easywork" "$install_path" 2> /dev/null; then
                chmod +x "$install_path"
                # Create short alias 'ew' in the same directory
                ln -sf "$(basename "$install_path")" "$(dirname "$install_path")/ew" 2> /dev/null || true
                if ! echo ":$PATH:" | grep -q ":$(dirname "$install_path"):"; then
                    log_warn "$(dirname "$install_path") 不在 \$PATH 中"
                    log_info "请添加以下行到你的 shell 配置: export PATH=\"$(dirname "$install_path"):\$PATH\""
                fi
                log_success "已安装 easywork 到 ${install_path}"
                log_info "运行 'easywork install' 完成组件配置"
            fi
        fi
    fi

    # Set up shell completions (skip in piped mode)
    if ! $IS_PIPED; then
        _setup_completions
    fi

    notify_if_update_available

    release_lock
}

# ─── CLI: Uninstall ───────────────────────────────────────────
cmd_uninstall() {
    local component="${1:-}"

    if ! manifest_exists; then
        log_error "未检测到安装记录（${MANIFEST_FILE} 不存在）"
        log_info "如果之前使用过 EasyWork，请手动清理模块配置文件:"
        log_info "  ~/.sh_config_custom, ~/.gitconfig, ~/.vimrc 等"
        return $EXIT_ERROR
    fi

    acquire_lock || return $?

    local targets=()
    if [[ -n "$component" ]]; then
        if ! manifest_section_exists "$component"; then
            log_error "组件 '$component' 未安装"
            release_lock
            return $EXIT_ERROR
        fi
        targets=("$component")
    else
        local installed
        installed="$(manifest_list_installed)"
        if [[ -z "${installed// /}" ]]; then
            log_info "没有已安装的组件"
            release_lock
            _finalize_uninstall
            return $EXIT_SUCCESS
        fi
        for name in $installed; do
            targets+=("$name")
        done
    fi

    # Confirm
    if [[ "${YES_MODE:-false}" != "true" ]]; then
        echo "将卸载以下组件:"
        for t in "${targets[@]}"; do
            echo "  - $t"
        done
        local answer
        read -r -p "  确认卸载？[Y/n] " answer
        if [[ "$answer" =~ ^[Nn] ]]; then
            log_info "已取消卸载"
            release_lock
            return $EXIT_SUCCESS
        fi
    fi

    echo ""
    local failed_modules=()
    for t in "${targets[@]}"; do
        log_info "[${t}] 卸载中..."
        if [[ -f "${LIB_DIR}/${t}.sh" ]]; then
            source "${LIB_DIR}/${t}.sh"
            if ! declare -f module_uninstall > /dev/null 2>&1; then
                log_error "[${t}] 模块文件加载失败，跳过卸载"
                failed_modules+=("$t")
                continue
            fi
            if module_uninstall; then
                manifest_remove_section "$t"
                log_success "[${t}] 已卸载"
            else
                log_warn "[${t}] 卸载时出现警告，继续..."
                failed_modules+=("$t")
            fi
        else
            log_warn "[${t}] 模块文件未找到，跳过卸载"
            failed_modules+=("$t")
        fi
        echo ""
    done

    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        log_warn "以下模块卸载失败（文件可能残留）: ${failed_modules[*]}"
    fi

    release_lock
    _finalize_uninstall
}

_finalize_uninstall() {
    _remove_completions

    local remaining
    remaining="$(manifest_list_installed | tr '\n' ' ')"
    if [[ -n "${remaining// /}" ]]; then
        log_info "以下组件仍安装: ${remaining}"
        log_info "配置文件和 manifest 已保留"
    else
        local answer="y"
        if [[ "${YES_MODE:-false}" != "true" ]]; then
            read -r -p "  保留 $(config_path) 以便将来使用？[Y/n] " answer
        elif [[ "${REMOVE_CONFIG:-false}" == "true" ]]; then
            answer="n"
        else
            answer="y"
        fi

        if [[ "$answer" =~ ^[Nn] ]]; then
            rm -f "$(ew_config_path)" "$(ew_legacy_config)"
            manifest_clear
            log_success "EasyWork 已完全移除 ✓"
        else
            log_info "配置文件已保留: $(config_path)"
            log_info "下次运行 easywork install 可直接复用身份信息"
        fi
    fi
}
