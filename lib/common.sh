#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# EasyWork — Common Library
# Provides: system detection, logging, download, manifest, config, managed sections,
#           module registry, concurrency lock, signal handling, exit codes.

set -euo pipefail

# Version (set by bin/easywork; default for standalone module usage)
EASYWORK_VERSION="${EASYWORK_VERSION:-0.0.0-dev}"

# EasyWork home directory — centralizes all CLI state (config, manifest, cache, completions).
# Overridable via EASYWORK_HOME for sandboxed/isolated runs (e.g. AI agents, tests).
EASYWORK_HOME="${EASYWORK_HOME:-${HOME}/.easywork}"

# ─── State Paths (single source of truth) ─────────────────────
# All tool state derives from EASYWORK_HOME. Modules must use these helpers
# instead of hardcoding paths.
ew_home() { echo "$EASYWORK_HOME"; }
ew_config_path() { echo "${EASYWORK_HOME}/config.toml"; }
ew_legacy_config() { echo "${EASYWORK_HOME}/config"; }
ew_manifest_path() { echo "${EASYWORK_HOME}/manifest"; }
ew_lib_cache() { echo "${EASYWORK_HOME}/lib/v${EASYWORK_VERSION}"; }
ew_completions_dir() { echo "${EASYWORK_HOME}/completions"; }

# Ensure the home directory exists
_ensure_easywork_home() {
    if [[ ! -d "$EASYWORK_HOME" ]]; then
        mkdir -p "$EASYWORK_HOME"
    fi
}

# ─── Exit Codes ───────────────────────────────────────────────
export EXIT_SUCCESS=0
export EXIT_ERROR=1
export EXIT_MISSING_DEPS=2
export EXIT_NETWORK=3
export EXIT_PERMISSION=4
export EXIT_LOCK=5
export EXIT_INTERRUPT=130

# ─── Color Support Detection ──────────────────────────────────
COLOR_ENABLED=false
if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_ENABLED=true
fi

C_BLACK=''
C_RED=''
C_GREEN=''
C_YELLOW=''
C_BLUE=''
C_PURPLE=''
C_CYAN=''
C_WHITE=''
C_RESET=''
if $COLOR_ENABLED; then
    C_BLACK=$'\e[30m'
    C_RED=$'\e[31m'
    C_GREEN=$'\e[32m'
    C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'
    C_PURPLE=$'\e[35m'
    C_CYAN=$'\e[36m'
    C_WHITE=$'\e[37m'
    C_RESET=$'\e[0m'
fi

# ─── Logging ──────────────────────────────────────────────────
log_info() {
    if [[ "${JSON_MODE:-false}" == "true" ]]; then
        printf "  %s●%s %s\n" "${C_CYAN}" "${C_RESET}" "$*" >&2
    else
        printf "  %s●%s %s\n" "${C_CYAN}" "${C_RESET}" "$*"
    fi
}
log_success() {
    if [[ "${JSON_MODE:-false}" == "true" ]]; then
        printf "  %s✓%s %s\n" "${C_GREEN}" "${C_RESET}" "$*" >&2
    else
        printf "  %s✓%s %s\n" "${C_GREEN}" "${C_RESET}" "$*"
    fi
}
log_warn() { printf "  %s!%s %s\n" "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_error() {
    EW_LAST_ERROR="$*"
    printf "  %s✗%s %s\n" "${C_RED}" "${C_RESET}" "$*" >&2
}
log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then printf "  %s[DEBUG]%s %s\n" "${C_PURPLE}" "${C_RESET}" "$*" >&2; fi
    return 0
}

# ─── System Detection ─────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

detect_shell() {
    basename "${SHELL:-/bin/bash}"
}

detect_pkg_manager() {
    if command -v brew > /dev/null 2>&1; then
        echo "brew"
    elif command -v apt-get > /dev/null 2>&1; then
        echo "apt-get"
    elif command -v dnf > /dev/null 2>&1; then
        echo "dnf"
    elif command -v yum > /dev/null 2>&1; then
        echo "yum"
    elif command -v pacman > /dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper > /dev/null 2>&1; then
        echo "zypper"
    elif command -v apk > /dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

has_cmd() { command -v "$1" > /dev/null 2>&1; }

# ─── Network ──────────────────────────────────────────────────
check_network() {
    local target="${1:-github.com}"
    local timeout="${2:-5}"
    if has_cmd curl; then
        curl -s --connect-timeout "$timeout" "https://${target}" > /dev/null 2>&1
    elif has_cmd wget; then
        wget -q --timeout="$timeout" -O /dev/null "https://${target}" 2> /dev/null
    else
        return 1
    fi
}

safe_download() {
    if [[ "${OFFLINE:-false}" == "true" ]]; then
        log_warn "离线模式：跳过下载"
        return $EXIT_NETWORK
    fi

    local expected_sha256=""
    local positional_args=()

    # Parse --sha256 flag before positional args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sha256)
                expected_sha256="$2"
                shift 2
                ;;
            --sha256=*)
                expected_sha256="${1#*=}"
                shift
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    set -- "${positional_args[@]}"
    local url="$1"
    local output="${2:-}"
    if (($# >= 2)); then
        shift 2
    else
        shift
    fi
    local opts=(-fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 --retry-connrefused)
    local curl_exit=0
    if [[ -n "$output" ]]; then
        curl "${opts[@]}" "$@" -o "$output" "$url" || curl_exit=$?
    else
        curl "${opts[@]}" "$@" "$url" || curl_exit=$?
    fi

    if [[ $curl_exit -ne 0 ]]; then
        return $curl_exit
    fi

    # SHA256 verification when checksum was requested
    if [[ -n "$expected_sha256" ]]; then
        if [[ -z "$output" ]]; then
            log_warn "--sha256 需要指定输出文件路径，跳过校验"
        else
            log_verbose "验证 SHA256: $output"
            if ! _sha256_check "$output" "$expected_sha256"; then
                log_error "文件完整性校验失败: $(basename "$output")"
                log_error "预期: $expected_sha256"
                rm -f "$output" 2> /dev/null || true
                return $EXIT_NETWORK
            fi
            log_verbose "SHA256 校验通过"
        fi
    fi

    return 0
}

# Compute SHA256 of a file and compare to expected hash.
# Returns 0 on match, 1 on mismatch or missing tool.
_sha256_check() {
    local file="$1"
    local expected="$2"
    local actual=""

    if has_cmd shasum; then
        actual="$(shasum -a 256 "$file" 2> /dev/null | cut -d' ' -f1)"
    elif has_cmd sha256sum; then
        actual="$(sha256sum "$file" 2> /dev/null | cut -d' ' -f1)"
    elif has_cmd openssl; then
        actual="$(openssl dgst -sha256 "$file" 2> /dev/null | cut -d' ' -f2)"
    else
        log_warn "未找到 SHA256 计算工具（shasum/sha256sum/openssl），跳过校验"
        return 0
    fi

    [[ -n "$actual" ]] || return 1

    # Case-insensitive comparison (bash 3.2 compatible — no ${var,,})
    local actual_lower expected_lower
    actual_lower="$(echo "$actual" | tr '[:upper:]' '[:lower:]')"
    expected_lower="$(echo "$expected" | tr '[:upper:]' '[:lower:]')"
    if [[ "$actual_lower" == "$expected_lower" ]]; then
        return 0
    fi
    log_verbose "SHA256 不匹配: 实际=${actual}, 预期=${expected}"
    return 1
}

# ─── File Operations ──────────────────────────────────────────
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local ts
        ts="$(date +%Y%m%dT%H%M%S)"
        local bak="${file}.bak.${ts}"
        if cp -p "$file" "$bak"; then
            echo "$bak"
        else
            log_error "无法创建备份: $bak"
            return 1
        fi
    fi
}

restore_backup() {
    local bak="$1"
    local target="$2"
    if [[ -f "$bak" ]]; then
        if mv "$bak" "$target" 2> /dev/null; then
            return 0
        fi
        log_error "恢复备份失败: ${bak} → ${target}（请手动处理）"
        return 1
    fi
    log_error "备份文件不存在: ${bak}"
    return 1
}

# ─── Managed Section Markers ──────────────────────────────────
managed_section_begin() {
    local version="${1:-unknown}"
    local comment="${2:-#}"
    echo "${comment} >>> EasyWork managed section begin (v${version}) >>>"
}

managed_section_end() {
    local comment="${1:-#}"
    echo "${comment} <<< EasyWork managed section end <<<"
}

replace_managed_section() {
    local file="$1"
    local version="$2"
    local content="$3"
    local comment="${4:-#}"
    local begin_marker
    begin_marker="$(managed_section_begin "$version" "$comment")"
    local end_marker
    end_marker="$(managed_section_end "$comment")"

    if [[ ! -f "$file" ]]; then
        # File doesn't exist — create with managed section
        {
            printf '%s\n' "$begin_marker"
            printf '%s\n' "$content"
            printf '%s\n' "$end_marker"
        } > "$file"
        return 0
    fi

    # Comment-agnostic detection: match distinctive marker text to avoid
    # false positives on content lines that casually mention "EasyWork"
    if grep -qE "managed section begin" "$file" 2> /dev/null; then
        # Managed section exists — replace it (comment-agnostic matching for cross-version compat)
        local tmpfile
        tmpfile="${file}.tmp.$$"
        _register_temp_file "$tmpfile"
        local in_section=false
        while IFS= read -r line; do
            if [[ "$line" =~ "managed section begin" ]]; then
                in_section=true
                printf '%s\n' "$begin_marker" >> "$tmpfile"
                printf '%s\n' "$content" >> "$tmpfile"
                continue
            fi
            if [[ "$line" =~ "managed section end" ]]; then
                in_section=false
                printf '%s\n' "$end_marker" >> "$tmpfile"
                continue
            fi
            if ! $in_section; then
                printf '%s\n' "$line" >> "$tmpfile"
            fi
        done < "$file"
        mv "$tmpfile" "$file"
    else
        # No managed section — prepend
        local tmpfile
        tmpfile="${file}.tmp.$$"
        _register_temp_file "$tmpfile"
        {
            printf '%s\n' "$begin_marker"
            printf '%s\n' "$content"
            printf '%s\n' "$end_marker"
            printf '%s\n' ""
            cat "$file"
        } > "$tmpfile"
        mv "$tmpfile" "$file"
    fi
}

# ─── Managed File Engine ──────────────────────────────────────
# High-level helpers so modules don't reimplement backup/remove/restore logic.

# Remove the EasyWork managed section from <file>, preserving other content.
# Returns 1 (and leaves the file untouched) if the markers are malformed.
remove_managed_section() {
    local file="$1"
    if [[ ! -f "$file" ]] || ! grep -qE "managed section begin" "$file" 2> /dev/null; then
        return 0
    fi
    local tmpfile
    tmpfile="${file}.tmp.$$"
    _register_temp_file "$tmpfile"
    : > "$tmpfile"
    local in_section=false
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ "managed section begin" ]]; then
            in_section=true
            continue
        fi
        if $in_section && [[ "$line" =~ "managed section end" ]]; then
            in_section=false
            continue
        fi
        if ! $in_section; then
            printf '%s\n' "$line" >> "$tmpfile"
        fi
    done < "$file"
    if $in_section; then
        log_warn "检测到不完整的 EasyWork 标记段，跳过修改: $file"
        rm -f "$tmpfile" 2> /dev/null || true
        return 1
    fi
    mv "$tmpfile" "$file"
    return 0
}

# Idempotently write a managed section into <target>.
# Backs up a pre-existing unmanaged file and records the path in <backup_var>
# (empty string if no backup was needed).
# Usage: apply_managed_file <target> <content> <comment> <backup_var>
apply_managed_file() {
    local target="$1"
    local content="$2"
    local comment="${3:-#}"
    local backup_var="${4:-}"

    local _ew_bak=""
    if [[ -f "$target" ]] && ! grep -qF "EasyWork managed section" "$target" 2> /dev/null; then
        _ew_bak="$(backup_file "$target")" || return 1
    fi
    if [[ -n "$backup_var" ]]; then
        printf -v "$backup_var" '%s' "$_ew_bak"
    fi
    replace_managed_section "$target" "$EASYWORK_VERSION" "$content" "$comment"
}

# Remove the managed section from <target>; restore the backup at <backup_path>
# (if any) afterwards. Usage: remove_managed_file <target> [backup_path]
remove_managed_file() {
    local target="$1"
    local backup_path="${2:-}"
    remove_managed_section "$target" || true
    if [[ -n "$backup_path" ]] && [[ -f "$backup_path" ]]; then
        restore_backup "$backup_path" "$target" || true
    fi
    return 0
}

# Resolve a variable by name (set -u safe). Usage: _indirect_get <name>
_indirect_get() {
    local name="$1"
    if [[ -z "$name" ]] || ! declare -p "$name" > /dev/null 2>&1; then
        printf '%s' ""
        return 0
    fi
    printf '%s' "${!name}"
}

# Declarative batch helpers driven by MODULE_DECLARE.
# Entry format: <target>|<content_fn>|<comment>|<backup_var>
apply_module_files() {
    # shellcheck disable=SC2154  # MODULE_DECLARE is defined by the sourcing module
    local entry target content_fn comment backup_var content
    for entry in "${MODULE_DECLARE[@]}"; do
        IFS='|' read -r target content_fn comment backup_var <<< "$entry"
        content="$("$content_fn")"
        apply_managed_file "$target" "$content" "${comment:-#}" "$backup_var" || return 1
    done
    return 0
}

remove_module_files() {
    # shellcheck disable=SC2154  # MODULE_DECLARE is defined by the sourcing module
    local entry target content_fn comment backup_var backup_path
    for entry in "${MODULE_DECLARE[@]}"; do
        IFS='|' read -r target content_fn comment backup_var <<< "$entry"
        : "$content_fn" # parsed for symmetry; unused on removal
        backup_path="$(_indirect_get "$backup_var")"
        remove_managed_file "$target" "$backup_path" || true
    done
    return 0
}

# ─── Manifest Management ──────────────────────────────────────
MANIFEST_FILE="$(ew_manifest_path)"

manifest_file() { echo "$MANIFEST_FILE"; }

manifest_exists() { [[ -f "$MANIFEST_FILE" ]]; }

manifest_read() {
    local key="$1"
    local default="${2:-}"
    if manifest_exists; then
        local val
        # Escape key for safe regex matching; || true prevents set -e from
        # firing when grep returns 1 (no match — a normal, expected case)
        local escaped_key
        escaped_key="$(_escape_regex "$key")"
        val="$(grep -E "^${escaped_key}=" "$MANIFEST_FILE" 2> /dev/null | head -1 | cut -d= -f2- | tr -d '\r' || true)"
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

manifest_get_version() {
    manifest_read "easywork_version" "0.0.0"
}

manifest_get_schema_version() {
    manifest_read "schema_version" "1"
}

manifest_section_exists() {
    local section="$1"
    manifest_exists && grep -qF "[$section]" "$MANIFEST_FILE" 2> /dev/null
}

manifest_section_installed() {
    local section="$1"
    manifest_list_installed | grep -qFx "$section"
}

manifest_list_installed() {
    if ! manifest_exists; then return 0; fi
    awk -F'=' '{ sub(/\r$/, "") } /^\[/{section=$1; gsub(/[\[\]]/,"",section)} /^installed=true$/{print section}' "$MANIFEST_FILE"
}

manifest_init() {
    local version="$1"
    _ensure_easywork_home
    cat > "$MANIFEST_FILE" << EOF
# EasyWork Manifest — auto-generated, do not edit
schema_version=1
easywork_version=${version}
install_date=$(date +%Y-%m-%dT%H:%M:%S%z)
EOF
}

manifest_write() {
    local manifest_data="$1"
    local tmpfile
    tmpfile="${MANIFEST_FILE}.tmp.$$"
    _register_temp_file "$tmpfile"
    printf '%s\n' "$manifest_data" > "$tmpfile"
    mv "$tmpfile" "$MANIFEST_FILE"
}

manifest_set_section() {
    local section="$1"
    local new_manifest=""
    local skip_section=false

    # Read existing manifest (minus the target section)
    if manifest_exists; then
        while IFS= read -r line; do
            line="${line%$'\r'}"
            if [[ "$line" == "[${section}]" ]]; then
                skip_section=true
                continue
            fi
            if $skip_section; then
                if [[ "$line" == "["*"]" ]]; then
                    skip_section=false
                    new_manifest+="$line"$'\n'
                fi
                continue
            fi
            new_manifest+="$line"$'\n'
        done < "$MANIFEST_FILE"
    else
        new_manifest="# EasyWork Manifest — auto-generated, do not edit"$'\n'
    fi

    # Append the new section with key=value pairs (if any)
    new_manifest+="[${section}]"$'\n'
    if [[ $# -gt 1 ]]; then
        shift
        local pair
        for pair in "$@"; do
            new_manifest+="${pair}"$'\n'
        done
    fi

    manifest_write "$new_manifest"
}

manifest_remove_section() {
    local section="$1"
    if ! manifest_exists; then return 0; fi
    local new_manifest=""
    local skip_section=false
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" == "[${section}]" ]]; then
            skip_section=true
            continue
        fi
        if $skip_section; then
            if [[ "$line" == "["*"]" ]]; then
                skip_section=false
                new_manifest+="$line"$'\n'
            fi
            continue
        fi
        new_manifest+="$line"$'\n'
    done < "$MANIFEST_FILE"

    # Remove trailing blank lines
    # Remove trailing blank lines (portable awk instead of BSD/GNU sed)
    new_manifest="$(printf '%s\n' "$new_manifest" | awk 'NF{last=NR}; {lines[NR]=$0} END{for(i=1;i<=last;i++) print lines[i]}')"
    printf '%s\n' "$new_manifest" > "$MANIFEST_FILE"
}

manifest_clear() {
    rm -f "$MANIFEST_FILE"
}

# ─── Date Formatting ─────────────────────────────────────────────
# Convert ISO 8601 date string to human-readable local time.
# Input:  2026-06-12T10:15:30+0800  (from manifest install_date)
# Output: 2026年06月12日 10:15:30 CST (varies by local timezone)
format_date_human() {
    local raw_date="$1"
    local fallback="${2:-${raw_date:-unknown}}"

    if [[ -z "$raw_date" ]] || [[ "$raw_date" == "unknown" ]]; then
        echo "$fallback"
        return
    fi

    local formatted
    case "$(detect_os)" in
        macos)
            # BSD date: -j for dry-run parse, -f for input format
            formatted="$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$raw_date" \
                "+%Y年%m月%d日 %H:%M:%S %Z" 2> /dev/null || true)"
            ;;
        *)
            # GNU date: -d for date string parsing
            formatted="$(date -d "$raw_date" \
                "+%Y年%m月%d日 %H:%M:%S %Z" 2> /dev/null || true)"
            ;;
    esac

    # Fallback to raw date if parsing fails (e.g. corrupt manifest)
    echo "${formatted:-$raw_date}"
}

# ─── Manifest Section Key Reader ─────────────────────────────────
# Read a key from within a specific manifest section.
# Usage: manifest_read_section_key <section> <key> [default]
manifest_read_section_key() {
    local section="$1"
    local key="$2"
    local default="${3:-}"

    if ! manifest_exists; then
        echo "$default"
        return
    fi

    # Escape key for safe regex matching
    local escaped_key
    escaped_key="$(_escape_regex "$key")"

    local in_section=false
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" == "[${section}]" ]]; then
            in_section=true
            continue
        fi
        if $in_section; then
            if [[ "$line" == "["*"]" ]]; then
                break # reached next section, stop
            fi
            if [[ "$line" =~ ^${escaped_key}= ]]; then
                echo "${line#*=}"
                return
            fi
        fi
    done < "$MANIFEST_FILE"
    echo "$default"
}

# Return a module's installation state: true|false|failed|absent
manifest_module_state() {
    local name="$1"
    if ! manifest_exists; then
        echo "absent"
        return 0
    fi
    local val
    val="$(manifest_read_section_key "$name" "installed" "")"
    echo "${val:-absent}"
}

# ─── Config File Management ───────────────────────────────────
CONFIG_FILE="$(ew_legacy_config)"

# Canonical config path (v2: config.toml).
config_path() { ew_config_path; }

# The file actually holding config: config.toml if present, else legacy ini.
config_active_file() {
    if [[ -f "$(ew_config_path)" ]]; then
        ew_config_path
    else
        ew_legacy_config
    fi
}

# True when either config.toml or the legacy ini exists.
config_exists() {
    [[ -f "$(ew_config_path)" ]] || [[ -f "$(ew_legacy_config)" ]]
}

# Load config into shell variables.
# Legacy ini ($CONFIG_FILE) is sourced as a read-only fallback; config.toml wins.
config_load() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
    local toml
    toml="$(ew_config_path)"
    if [[ -f "$toml" ]]; then
        GIT_PERSONAL_NAME="$(cfg_get 'git.identities.personal.name' "${GIT_PERSONAL_NAME:-}")"
        GIT_PERSONAL_EMAIL="$(cfg_get 'git.identities.personal.email' "${GIT_PERSONAL_EMAIL:-}")"
        GIT_WORK_NAME="$(cfg_get 'git.identities.work.name' "${GIT_WORK_NAME:-}")"
        GIT_WORK_EMAIL="$(cfg_get 'git.identities.work.email' "${GIT_WORK_EMAIL:-}")"
    fi
}

# ─── TOML Config Accessors (config.toml, v1 subset) ────────────
# v1 supports only scalar values (string/bool/integer), dotted section
# names, and '#' comments. No arrays or inline tables.

# Trim leading/trailing whitespace (bash 3.2 compatible).
_cfg_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Extract the scalar from a raw 'key = value' right-hand side.
# Quoted values support the escapes emitted by cfg_set: \\ \" \n \t.
_cfg_value() {
    local raw="$1"
    raw="$(_cfg_trim "$raw")"
    if [[ "$raw" == \"* ]]; then
        raw="${raw#\"}"
        local out="" ch esc=false i
        for ((i = 0; i < ${#raw}; i++)); do
            ch="${raw:i:1}"
            if $esc; then
                case "$ch" in
                    '"') out+='"' ;;
                    "\\") out+="\\" ;;
                    n) out+=$'\n' ;;
                    t) out+=$'\t' ;;
                    *) out+="\\$ch" ;;
                esac
                esc=false
                continue
            fi
            if [[ "$ch" == "\\" ]]; then
                esc=true
                continue
            fi
            if [[ "$ch" == '"' ]]; then
                break
            fi
            out+="$ch"
        done
        printf '%s' "$out"
    else
        raw="${raw%%#*}"
        raw="$(_cfg_trim "$raw")"
        printf '%s' "$raw"
    fi
}

# Read a scalar from config.toml by dotted key.
# Usage: cfg_get <section.key> [default]
cfg_get() {
    local key="$1"
    local default="${2:-}"
    local file
    file="$(ew_config_path)"
    if [[ ! -f "$file" ]]; then
        printf '%s' "$default"
        return 0
    fi

    local want_section="" want_key="$key"
    if [[ "$key" == *.* ]]; then
        want_section="${key%.*}"
        want_key="${key##*.}"
    fi

    local line current_section="" lhs
    while IFS= read -r line; do
        line="${line%%$'\r'}"
        line="$(_cfg_trim "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == \[*\] ]]; then
            current_section="${line#[}"
            current_section="${current_section%]}"
            current_section="$(_cfg_trim "$current_section")"
            continue
        fi
        [[ "$current_section" == "$want_section" ]] || continue
        if [[ "$line" == "$want_key"*"="* ]]; then
            lhs="${line%%=*}"
            lhs="$(_cfg_trim "$lhs")"
            [[ "$lhs" == "$want_key" ]] || continue
            _cfg_value "${line#*=}"
            return 0
        fi
    done < "$file"

    printf '%s' "$default"
    return 0
}

# Read a boolean from config.toml (normalized to true/false).
cfg_get_bool() {
    local key="$1"
    local default="${2:-false}"
    local v
    v="$(cfg_get "$key" "$default")"
    case "$v" in
        true | TRUE | 1 | yes | on) printf 'true' ;;
        false | FALSE | 0 | no | off) printf 'false' ;;
        *) printf '%s' "$default" ;;
    esac
}

# Lightweight validation of config.toml (syntax + schema_version).
# Returns 0 if OK (or file absent), 1 otherwise.
cfg_valid() {
    local file
    file="$(ew_config_path)"
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    local schema
    schema="$(cfg_get schema_version 1)"
    if [[ "$schema" != "1" ]]; then
        log_warn "config.toml schema_version=${schema}，期望 1"
        return 1
    fi
    return 0
}

# Upsert a scalar value in config.toml (creates file/section as needed).
# Keeps unrelated lines intact. Values are written as TOML double-quoted strings.
# Usage: cfg_set <section.key> <value>
cfg_set() {
    local key="$1"
    local value="$2"
    local file
    file="$(ew_config_path)"

    local section="" keyname="$key"
    if [[ "$key" == *.* ]]; then
        section="${key%.*}"
        keyname="${key##*.}"
    fi

    _ensure_easywork_home
    if [[ ! -f "$file" ]]; then
        printf 'schema_version = 1\n' > "$file"
    fi

    local esc="$value"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"

    local tmpfile
    tmpfile="${file}.tmp.$$"
    _register_temp_file "$tmpfile"

    local section_found=false key_written=false in_target=false
    # 无点号键为顶层键：初始即处于目标上下文
    if [[ -z "$section" ]]; then
        in_target=true
        section_found=true
    fi
    local line sec lhs
    while IFS= read -r line; do
        if [[ "$line" == \[*\] ]]; then
            if $in_target && ! $key_written; then
                printf '%s = "%s"\n' "$keyname" "$esc" >> "$tmpfile"
                key_written=true
            fi
            sec="${line#[}"
            sec="${sec%]}"
            sec="$(_cfg_trim "$sec")"
            if [[ "$sec" == "$section" ]]; then
                in_target=true
                section_found=true
            else
                in_target=false
            fi
            printf '%s\n' "$line" >> "$tmpfile"
            continue
        fi
        if $in_target; then
            lhs="${line%%=*}"
            lhs="$(_cfg_trim "$lhs")"
            if [[ "$lhs" == "$keyname" ]]; then
                printf '%s = "%s"\n' "$keyname" "$esc" >> "$tmpfile"
                key_written=true
                continue
            fi
        fi
        printf '%s\n' "$line" >> "$tmpfile"
    done < "$file"

    if $in_target && ! $key_written; then
        printf '%s = "%s"\n' "$keyname" "$esc" >> "$tmpfile"
        key_written=true
    fi

    if ! $section_found; then
        printf '\n[%s]\n' "$section" >> "$tmpfile"
        printf '%s = "%s"\n' "$keyname" "$esc" >> "$tmpfile"
    fi

    mv "$tmpfile" "$file"
    return 0
}

# Migrate the legacy ini config (CONFIG_FILE) to config.toml (once).
# No-op if config.toml already exists or legacy config is absent.
config_migrate() {
    local toml
    toml="$(ew_config_path)"
    if [[ -f "$toml" ]]; then
        return 0
    fi

    local legacy
    legacy="$(ew_legacy_config)"
    if [[ ! -f "$legacy" ]]; then
        return 0
    fi

    # shellcheck source=/dev/null
    source "$legacy"

    _ensure_easywork_home
    {
        echo "schema_version = 1"
        echo ""
        echo "[git.identities.personal]"
        echo "name  = \"${GIT_PERSONAL_NAME:-}\""
        echo "email = \"${GIT_PERSONAL_EMAIL:-}\""
        echo ""
        echo "[git.identities.work]"
        echo "name  = \"${GIT_WORK_NAME:-}\""
        echo "email = \"${GIT_WORK_EMAIL:-}\""
    } > "$toml"
    log_info "已迁移旧配置到 $(ew_config_path)"
    return 0
}

# Ensure config.toml exists: migrate legacy ini, else write a default template.
_ensure_config_toml() {
    _ensure_easywork_home
    local toml
    toml="$(ew_config_path)"
    if [[ -f "$toml" ]]; then
        return 0
    fi
    if [[ -f "$(ew_legacy_config)" ]]; then
        config_migrate
        return 0
    fi
    cat > "$toml" << 'EOC'
# EasyWork 配置文件（v2）
# 编辑: easywork config edit
# 或:   easywork config set <键> <值>
schema_version = 1

[shell]
enable_aliases      = true
enable_fancy_prompt = false
enable_ohmyzsh      = false
enable_net_tools    = false

[git]
identity = "personal"
scope    = "global"

[ai_tools]
install = true
EOC
    log_info "已创建配置文件: $toml"
    log_info "编辑此文件或运行: easywork config edit"
}

config_init() {
    _ensure_config_toml
    config_load
}

config_show() {
    local active
    active="$(config_active_file)"
    if [[ ! -f "$active" ]]; then
        echo "配置文件路径: $(config_path)"
        echo ""
        echo "（配置文件不存在，运行 easywork install 自动创建）"
        return 0
    fi

    echo "配置文件路径: $active"
    if [[ "$active" != "$(ew_config_path)" ]]; then
        echo "（旧版 ini；运行 easywork config edit 将迁移到 config.toml）"
    fi
    echo ""

    # --- File Metadata ---
    local file_size line_count mod_time
    file_size="$(wc -c < "$active" | tr -d ' ')"
    line_count="$(wc -l < "$active" | tr -d ' ')"
    if [[ "$(detect_os)" == "macos" ]]; then
        mod_time="$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$active" 2> /dev/null || echo 'unknown')"
    else
        mod_time="$(stat -c "%y" "$active" 2> /dev/null | cut -d. -f1 || echo 'unknown')"
    fi

    echo "  文件大小: ${file_size} 字节"
    echo "  行数:     ${line_count} 行"
    echo "  修改时间: ${mod_time}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    cat "$active"

    # Show hint when the file has no real key/value lines (comments/blank only)
    if ! grep -qE '^[^#[:space:]].*=' "$active" 2> /dev/null; then
        echo ""
        echo "（配置文件尚无配置项，可通过 'easywork config edit' 编辑添加）"
    fi
}

config_edit() {
    _ensure_config_toml
    local editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        for e in vim nano vi; do
            if has_cmd "$e"; then
                editor="$e"
                break
            fi
        done
    fi
    if [[ -z "$editor" ]]; then
        log_error "未找到编辑器，请设置 \$EDITOR 环境变量"
        return 1
    fi
    if ! "$editor" "$(ew_config_path)"; then
        # Editor exited non-zero (e.g. :cq in vim) — ignore, not a fatal error
        :
    fi
}

# ─── Module Registry ──────────────────────────────────────────
# Uses indexed arrays for bash 3.2+ compatibility (macOS default)
MODULE_NAMES=()
MODULE_DESCRIPTIONS=()
MODULE_PRIORITY_VALUES=()

register_module() {
    local name="$1"
    local description="$2"
    local priority="${3:-50}"

    # Validate: module name must not conflict with reserved words
    local reserved="^(install|uninstall|config|version|update)$"
    if [[ "$name" =~ $reserved ]]; then
        log_error "模块名 '$name' 与内置命令冲突"
        exit $EXIT_ERROR
    fi

    # Validate: no whitespace, control chars, path traversal, or special chars
    if [[ "$name" =~ [[:space:]] ]] || [[ "$name" =~ [[:cntrl:]] ]]; then
        log_error "模块名包含非法空白/控制字符: '$name'"
        exit $EXIT_ERROR
    fi
    if [[ "$name" =~ [/] ]] || [[ "$name" == ".." ]]; then
        log_error "模块名包含路径穿越字符: '$name'"
        exit $EXIT_ERROR
    fi
    if [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
        log_error "模块名包含非法字符（仅允许字母、数字、-、_）: '$name'"
        exit $EXIT_ERROR
    fi

    # Prevent duplicate registration
    if module_registered "$name"; then
        return 0
    fi

    MODULE_NAMES+=("$name")
    MODULE_DESCRIPTIONS+=("$description")
    MODULE_PRIORITY_VALUES+=("$priority")
}

module_registered() {
    local name="$1"
    local n
    [[ ${#MODULE_NAMES[@]} -eq 0 ]] && return 1
    for n in "${MODULE_NAMES[@]}"; do
        [[ "$n" == "$name" ]] && return 0
    done
    return 1
}

_get_module_index() {
    local name="$1"
    local i
    [[ ${#MODULE_NAMES[@]} -eq 0 ]] && return 1
    for i in "${!MODULE_NAMES[@]}"; do
        if [[ "${MODULE_NAMES[$i]}" == "$name" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

list_modules() {
    local entries=() i
    [[ ${#MODULE_NAMES[@]} -eq 0 ]] && return 0
    for i in "${!MODULE_NAMES[@]}"; do
        entries+=("${MODULE_PRIORITY_VALUES[$i]}|${MODULE_NAMES[$i]}|${MODULE_DESCRIPTIONS[$i]}")
    done
    # --json 时日志走 stderr，避免污染 stdout 数据
    local out=/dev/stdout
    [[ "${JSON_MODE:-false}" == "true" ]] && out=/dev/stderr
    if [[ ${#entries[@]} -gt 0 ]]; then
        printf '%s\n' "${entries[@]}" | sort -t'|' -k1 -n | while IFS='|' read -r prio name desc; do
            [[ -n "$name" ]] && printf "  %-30s %s\n" "$name" "$desc" > "$out"
        done
    fi
}

list_modules_sorted() {
    local entries=() i
    [[ ${#MODULE_NAMES[@]} -eq 0 ]] && return 0
    for i in "${!MODULE_NAMES[@]}"; do
        entries+=("${MODULE_PRIORITY_VALUES[$i]}|${MODULE_NAMES[$i]}")
    done
    if [[ ${#entries[@]} -gt 0 ]]; then
        printf '%s\n' "${entries[@]}" | sort -t'|' -k1 -n | cut -d'|' -f2
    fi
}

# ─── Semver Comparison ───────────────────────────────────────
# Returns: 0=equal, 1=first is newer, 2=second is newer
_semver_compare() {
    local IFS=.
    local i
    local a
    IFS=. read -ra a <<< "${1:-0.0.0}"
    local b
    IFS=. read -ra b <<< "${2:-0.0.0}"
    for i in 0 1 2; do
        local ai=${a[$i]:-0}
        # Strip leading v prefix (GitHub tag style) and pre-release suffix
        ai="${ai#v}"
        ai="${ai%%[-+]*}"
        ai="${ai:-0}"
        local bi=${b[$i]:-0}
        bi="${bi#v}"
        bi="${bi%%[-+]*}"
        bi="${bi:-0}"
        if ((ai > bi)); then return 1; fi
        if ((ai < bi)); then return 2; fi
    done
    return 0
}

_semver_is_newer() {
    # Returns 0 (true) if $1 > $2
    _semver_compare "$1" "$2"
    [[ $? -eq 1 ]]
}

# ─── Update Check ──────────────────────────────
# Release API (overridable for forks/mirrors; bin/easywork also sets it).
EASYWORK_API_URL="${EASYWORK_API_URL:-https://api.github.com/repos/EasyIndie/EasyWork/releases/latest}"

# Fetch the latest released version (normalized to 'vX.Y.Z'), or empty on failure.
# Uses a short timeout so it never noticeably blocks install/status.
_fetch_latest_version() {
    local resp ver
    resp="$(curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 3 --max-time 6 \
        -H 'Accept: application/vnd.github+json' "$EASYWORK_API_URL" 2> /dev/null || true)"
    ver="$(printf '%s' "$resp" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    [[ -n "$ver" ]] || return 0
    [[ "$ver" == v* ]] || ver="v${ver}"
    printf '%s' "$ver"
}

# Resolve the latest release version, cached for 24h (empty on no info/failure).
resolve_latest_version() {
    local cache="${EASYWORK_HOME}/.last_update_check"
    local now
    now="$(date +%s)"
    if [[ -f "$cache" ]]; then
        local last cached
        last="$(sed -n '1p' "$cache" 2> /dev/null || true)"
        cached="$(sed -n '2p' "$cache" 2> /dev/null || true)"
        case "$last" in
            '' | *[!0-9]*) last=0 ;;
        esac
        if ((now - last < 86400)); then
            printf '%s' "$cached"
            return 0
        fi
    fi
    local latest
    latest="$(_fetch_latest_version)"
    _ensure_easywork_home
    printf '%s\n%s\n' "$now" "$latest" > "$cache" 2> /dev/null || true
    printf '%s' "$latest"
}

# JSON fragment describing update availability (for --json outputs).
# Shape: {"latest":"vX.Y.Z"|"null","available":true|false}
update_json_fragment() {
    if [[ "${OFFLINE:-false}" == "true" ]]; then
        printf '{"latest":null,"available":false}'
        return 0
    fi
    local latest
    latest="$(resolve_latest_version)"
    if [[ -z "$latest" ]]; then
        printf '{"latest":null,"available":false}'
        return 0
    fi
    local available=false
    _semver_is_newer "$latest" "$EASYWORK_VERSION" && available=true
    printf '{"latest":"%s","available":%s}' "$(json_escape "$latest")" "$available"
}

# Non-blocking "new version available" notice (human mode only).
notify_if_update_available() {
    [[ "${OFFLINE:-false}" == "true" ]] && return 0
    [[ "${JSON_MODE:-false}" == "true" ]] && return 0
    local latest
    latest="$(resolve_latest_version)"
    [[ -n "$latest" ]] || return 0
    if _semver_is_newer "$latest" "$EASYWORK_VERSION"; then
        log_info "发现新版本 ${latest}（当前 ${EASYWORK_VERSION}）: 运行 easywork update 升级"
    fi
    return 0
}

# ─── Concurrency Lock ─────────────────────────────────────────
LOCK_FILE="${TMPDIR:-/tmp}/easywork.lock"
# Use fixed fd=200 for bash 3.2 compatibility (no {varname}> auto-assignment)
LOCK_FD=200

acquire_lock() {
    local timeout="${1:-30}"

    # Try flock (Linux) first — not available on macOS by default.
    # When flock is absent or fails, we fall through to shlock or mkdir.
    if has_cmd flock; then
        eval "exec ${LOCK_FD}> \"$LOCK_FILE\""
        if flock -w "$timeout" "$LOCK_FD" 2> /dev/null; then
            return 0
        fi
        eval "exec ${LOCK_FD}>&-" 2> /dev/null || true
    fi

    # Try shlock (macOS)
    if has_cmd shlock; then
        if shlock -f "$LOCK_FILE" -p $$ 2> /dev/null; then
            return 0
        fi
    fi

    # Fallback: mkdir atomic operation
    local lock_dir="${LOCK_FILE}.dir"
    local start
    start=$(date +%s)
    while ! mkdir "$lock_dir" 2> /dev/null; do
        local now
        now=$(date +%s)
        if ((now - start >= timeout)); then
            log_error "无法获取锁，可能有另一个 easywork 实例正在运行"
            return $EXIT_LOCK
        fi
        sleep 0.5
    done
    # Save lock_dir path for cleanup (overwrite LOCK_FILE to signal mkdir was used)
    LOCK_FILE="$lock_dir"
    return 0
}

release_lock() {
    # Release flock if active
    if [[ -n "${LOCK_FD:-}" ]]; then
        flock -u "$LOCK_FD" 2> /dev/null || true
        eval "exec ${LOCK_FD}>&-" 2> /dev/null || true
    fi
    # Clean up mkdir-based lock directory
    if [[ "$LOCK_FILE" == *.dir ]] && [[ -d "$LOCK_FILE" ]]; then
        rmdir "$LOCK_FILE" 2> /dev/null || true
    elif [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE" 2> /dev/null || true
    fi
    # Preserve the numeric fd constant so re-acquire works correctly.
    # acquire_lock uses eval "exec ${LOCK_FD}> ..." — clearing this to ""
    # would redirect stdout on the next call instead of opening a file descriptor.
    : "${LOCK_FD:=200}"
}

# ─── Signal Handling ──────────────────────────────────────────

cleanup_on_interrupt() {
    log_warn "操作被中断"
    release_lock
    if [[ -n "$TEMP_FILES" ]]; then
        # shellcheck disable=SC2086
        rm -f -- $TEMP_FILES
    fi
    # Safety net: clean common tmp patterns for this PID
    rm -f "${EASYWORK_HOME}/"*.tmp."$$" 2> /dev/null || true
    rm -f "${TMPDIR:-/tmp}/easywork"*.tmp."$$" 2> /dev/null || true
    exit $EXIT_INTERRUPT
}

trap cleanup_on_interrupt INT TERM

# ─── Preflight Check ──────────────────────────────────────────
preflight_check() {
    local missing=()
    local optional_missing=()

    has_cmd curl || missing+=("curl")
    has_cmd git || missing+=("git")
    has_cmd bash || missing+=("bash")
    has_cmd awk || missing+=("awk")
    has_cmd sed || missing+=("sed")

    if ! has_cmd zsh; then
        optional_missing+=("zsh (Oh My Zsh 将跳过)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必须依赖: ${missing[*]}"
        log_error "请先安装后重试"
        return $EXIT_MISSING_DEPS
    fi

    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        log_warn "缺少可选依赖: ${optional_missing[*]}"
    fi

    if ! check_network; then
        log_warn "网络不可达 (github.com)，部分功能可能不可用"
    fi

    return $EXIT_SUCCESS
}

# ─── Dependency Installer ─────────────────────────────────────
ensure_deps() {
    local deps=("$@")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! has_cmd "$dep"; then
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少依赖: ${missing[*]}"
        return $EXIT_MISSING_DEPS
    fi
    return $EXIT_SUCCESS
}

# ─── String Escaping Helpers ──────────────────────────────────

# Escape regex metacharacters for safe use in grep -E / [[ =~ ]]
_escape_regex() {
    sed -e 's/\\/\\\\/g' \
        -e 's/\./\\./g' \
        -e 's/\*/\\*/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/\^/\\^/g' \
        -e 's/\$/\\$/g' \
        -e 's/|/\\|/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/\+/\\+/g' \
        -e 's/?/\\?/g' \
        <<< "$1"
}

# Escape value for safe use in sed s/// replacement (handles \ & /)
_escape_sed_replacement() {
    sed -e 's/\\/\\\\/g' \
        -e 's/&/\\&/g' \
        -e 's/\//\\\//g' \
        <<< "$1"
}

# Escape a string for embedding inside a JSON double-quoted string.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# 输出 --json 失败信封到 stdout：{"ok":false,...,"error":{"code":N,"message":...}}
# 用法: _json_error_envelope <command> <code> <message>
_json_error_envelope() {
    local cmd="$1" code="$2" msg="$3"
    printf '{"ok":false,"command":"%s","data":null,"error":{"code":%s,"message":"%s"}}\n' \
        "$(json_escape "$cmd")" "$code" "$(json_escape "$msg")"
}

# ─── Temp File Tracking (for signal cleanup) ──────────────────
TEMP_FILES=""

# 最近一次 log_error 的消息（用于 --json 错误信封）
EW_LAST_ERROR=""

_register_temp_file() {
    TEMP_FILES="${TEMP_FILES}${TEMP_FILES:+ }$1"
}
