#!/usr/bin/env bash
# EasyWork — 安装 Go CLI（跨平台：Unix + Windows Git Bash/MSYS/Cygwin）
#
# 用法: bash scripts/install.sh   （make install 会先 build 再调用本脚本）
#
# Unix   : 安装到 /usr/local/bin（可写）否则 ~/.local/bin；生成 easywork 与 ew 符号链接
# Windows: 安装 easywork.exe + ew.exe 到 ~/.local/bin，并确保用户 PATH / PATHEXT 含 .EXE
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

is_windows() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

bin=".build/ew"
if is_windows; then
    bin=".build/ew.exe"
fi
if [[ ! -f "$bin" ]]; then
    echo "缺少 $bin，请先运行: make build（或 go build -o $bin ./cmd/ew）" >&2
    exit 1
fi

install_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    chmod +x "$dst" 2> /dev/null || true
}

if is_windows; then
    dir="${EASYWORK_BIN_DIR:-$HOME/.local/bin}"
    install_file "$bin" "$dir/easywork.exe"
    install_file "$bin" "$dir/ew.exe"

    # 补齐用户 PATH 与 PATHEXT（仅对新会话生效）
    ps=""
    if command -v powershell > /dev/null 2>&1; then
        ps="powershell"
    elif command -v pwsh > /dev/null 2>&1; then
        ps="pwsh"
    elif [[ -x "${SYSTEMROOT:-/c/Windows}/System32/WindowsPowerShell/v1.0/powershell.exe" ]]; then
        ps="${SYSTEMROOT:-/c/Windows}/System32/WindowsPowerShell/v1.0/powershell.exe"
    fi

    if command -v cygpath > /dev/null 2>&1 && [[ -n "$ps" ]]; then
        win_dir="$(cygpath -w "$dir")"
        # PowerShell 脚本用单引号以免 shell 展开；参数经环境变量传入。
        # shellcheck disable=SC2016
        EW_INSTALL_DIR_WIN="$win_dir" "$ps" -NoProfile -Command '
            $d = $env:EW_INSTALL_DIR_WIN
            $p = [Environment]::GetEnvironmentVariable("Path", "User")
            if (-not $p) { $p = "" }
            if (($p -split ";") -notcontains $d) {
                [Environment]::SetEnvironmentVariable("Path", ($p.TrimEnd(";") + ";" + $d), "User")
                Write-Output ("已加入用户 PATH: " + $d)
            } else {
                Write-Output ("用户 PATH 已包含: " + $d)
            }
            $pe = [Environment]::GetEnvironmentVariable("PATHEXT", "User")
            if (-not $pe) { $pe = [Environment]::GetEnvironmentVariable("PATHEXT", "Machine") }
            if (-not $pe) { $pe = ".COM;.EXE;.BAT;.CMD" }
            if (($pe.ToUpper() -split ";") -notcontains ".EXE") {
                [Environment]::SetEnvironmentVariable("PATHEXT", ($pe.TrimEnd(";") + ";.EXE"), "User")
                Write-Output "已补 PATHEXT: .EXE"
            } else {
                Write-Output "PATHEXT 已含 .EXE"
            }
        '
    else
        echo "提示: 未找到 cygpath/powershell，请手动把 $dir 加入 PATH" >&2
    fi

    echo "✅ 已安装: $dir/easywork.exe, $dir/ew.exe"
    echo "   新开一个终端后可用: ew version"
else
    if [[ -w /usr/local/bin ]]; then
        dir="/usr/local/bin"
    elif [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2> /dev/null; then
        dir="$HOME/.local/bin"
    else
        echo "无法写入 /usr/local/bin 或 ~/.local/bin，请手动安装 $bin" >&2
        exit 1
    fi
    install_file "$bin" "$dir/easywork"
    ln -sf easywork "$dir/ew"
    echo "✅ 已安装: $dir/easywork (别名 ew)"
fi
