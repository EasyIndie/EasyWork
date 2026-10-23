#!/usr/bin/env bash
# EasyWork — conformance test helpers (black-box)
#
# 这些测试**不** source 任何 lib/*.sh：它们只通过 $EW_BIN 调用实现，并在
# 独立沙箱 HOME/EASYWORK_HOME 中断言 stdout 字节、退出码与生成文件。
# 因此同一套件可分别验证 Bash 与 Go 实现（见 tests/conformance/run.sh）。

EW_BIN="${EW_BIN:?conformance 需要通过 EW_BIN 指定被测二进制}"
# 被测引擎标识（bash|go）：用于仅 Go 实现具备的 v2.x 增量特性。
EW_ENGINE="${EW_ENGINE:-}"

setup() {
    TEST_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/ewconf.XXXXXX")"
    export TEST_HOME
    export HOME="$TEST_HOME"
    export EASYWORK_HOME="$TEST_HOME/.easywork"
    export EASYWORK_API_URL="http://127.0.0.1:1/" # 永不触网
    export NO_COLOR=1
    # 断言按 UTF-8 字节比较：禁用 Windows 管道下的 ANSI 代码页转码
    export EASYWORK_OUTPUT_ENCODING=utf8
    # 防止 piped 自安装写到真实 /usr/local/bin（覆盖 Go 引擎）
    export EASYWORK_BIN_DIR="$TEST_HOME/.local/bin"
    mkdir -p "$EASYWORK_BIN_DIR"
    unset EASYWORK_CHANNEL EASYWORK_RAW_URL EASYWORK_RELEASE_URL EASYWORK_WEB_URL 2> /dev/null || true
    mkdir -p "$EASYWORK_HOME"
}

teardown() {
    rm -rf "$TEST_HOME"
}

ew() { "$EW_BIN" "$@"; }

# is_windows：在 Git Bash（MINGW/MSYS/CYGWIN）下为真。
is_windows() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

# completion_rc：补全注入的 rc/profile 文件（Windows 为 PowerShell profile）。
completion_rc() {
    if is_windows; then
        printf '%s\n' "$HOME/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
    else
        printf '%s\n' "$HOME/.zshrc"
    fi
}

# shell_target：shell 模块写 managed section 的目标文件。
shell_target() {
    if is_windows; then
        printf '%s\n' "$HOME/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
    else
        printf '%s\n' "$HOME/.sh_config_custom"
    fi
}

# native_path：MSYS 会把传给原生二进制的 POSIX 路径转成 Windows 形式，
# 比较 Go 输出时需用 cygpath -m 得到同样的字符串。
native_path() {
    if is_windows; then
        cygpath -m "$1"
    else
        printf '%s' "$1"
    fi
}

# 运行命令，stdout 存 $EW_OUT，退出码存 $EW_RC，stderr 存 $EW_ERR。
ew_capture() {
    EW_RC=0
    EW_OUT="$("$EW_BIN" "$@" 2> "$TEST_HOME/.stderr")" || EW_RC=$?
    EW_ERR="$(cat "$TEST_HOME/.stderr")"
}

# 在沙箱中写一个 config.toml。
write_config() {
    cat > "$EASYWORK_HOME/config.toml"
}

# 在沙箱中写一个 manifest。
write_manifest() {
    cat > "$EASYWORK_HOME/manifest"
}
