package cli

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/modules"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

// completionMarker 是补全注入标记（契约八/C8 的一部分，避免重复注入）。
const completionMarker = "# EasyWork completion"

type completionRC struct {
	shell string // bash | zsh | powershell
	path  string
}

// moduleWords 返回按优先级排序的补全候选：模块名 + `module/component` + 子组件简写。
func moduleWords() string {
	sorted := modules.Sorted()
	words := make([]string, 0, len(sorted)*2)
	for _, m := range sorted {
		words = append(words, m.Name())
		words = append(words, modules.Aliases(m)...)
	}
	for _, m := range sorted {
		for _, c := range modules.Components(m) {
			words = append(words, m.Name()+"/"+c.Name)
		}
	}
	// 子组件简写（如 `ew install claude`）。
	for _, m := range sorted {
		for _, c := range modules.Components(m) {
			words = append(words, c.Name)
		}
	}
	return strings.Join(words, " ")
}

// completionRCFiles 返回应注入补全的 shell 配置文件（跨平台）。
func (a *App) completionRCFiles() []completionRC {
	if platform.DetectOS() == platform.Windows {
		return []completionRC{{shell: "powershell", path: a.Env.PowerShellProfile()}}
	}
	home := a.Env.Home
	files := []completionRC{{shell: "zsh", path: filepath.Join(home, ".zshrc")}}
	primary := filepath.Join(home, ".bashrc")
	if platform.DetectOS() == platform.MacOS {
		primary = filepath.Join(home, ".bash_profile")
	}
	files = append(files, completionRC{shell: "bash", path: primary})
	alt := filepath.Join(home, ".bashrc")
	if primary == alt {
		alt = filepath.Join(home, ".bash_profile")
	}
	if fileExists(alt) {
		files = append(files, completionRC{shell: "bash", path: alt})
	}
	return files
}

// completionSourceLine 生成按 shell 注入的 source 行。
func (a *App) completionSourceLine(shell, dir string) string {
	d := platform.ToSlash(dir)
	switch shell {
	case "zsh":
		return "source " + d + "/_easywork  " + completionMarker
	case "powershell":
		return ". \"" + d + "/easywork.ps1\"  " + completionMarker
	default:
		return "source " + d + "/easywork.bash  " + completionMarker
	}
}

// setupCompletions 生成补全文件并注入 shell 配置（幂等）。
func (a *App) setupCompletions() int {
	if a.DryRun {
		a.Log.Info("[DRY-RUN] 将配置 shell 补全")
		return 0
	}
	dir := a.Env.CompletionsDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return a.fail(1, "创建补全目录失败: "+err.Error())
	}
	mods := moduleWords()

	files := map[string]string{
		"easywork.bash": bashCompletion(a.Version, mods),
		"_easywork":     zshCompletion(a.Version, mods),
		"easywork.ps1":  pwshCompletion(a.Version, mods),
	}
	for name, content := range files {
		if err := platform.AtomicWrite(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			return a.fail(1, "写入补全文件失败: "+err.Error())
		}
	}

	injected := false
	for _, rc := range a.completionRCFiles() {
		desired := a.completionSourceLine(rc.shell, dir)
		// 已注入且路径当前 → 幂等跳过；若存在但路径过期（如 EASYWORK_HOME 变更）
		// 则移除旧行后重新写入。
		if rcHasLine(rc.path, desired) {
			continue
		}
		if _, err := os.Stat(rc.path); err != nil {
			if err := platform.AtomicWrite(rc.path, nil, 0o644); err != nil {
				continue
			}
		}
		if rcHasCompletionMarker(rc.path) {
			_ = stripMarkerLine(rc.path)
		}
		data, _ := os.ReadFile(rc.path)
		content := string(data)
		if content != "" && !strings.HasSuffix(content, "\n") {
			content += "\n"
		}
		content += "\n" + desired + "\n"
		if err := platform.AtomicWrite(rc.path, []byte(content), 0o644); err != nil {
			continue
		}
		a.Log.Info("Shell 补全已注入: " + platform.ToSlash(rc.path))
		injected = true
	}
	if injected {
		a.Log.Success("Shell 补全已配置（重启 shell 后生效）")
	}
	return 0
}

// removeCompletions 移除补全文件与注入行。
func (a *App) removeCompletions() int {
	if a.DryRun {
		a.Log.Info("[DRY-RUN] 将移除 shell 补全配置")
		return 0
	}
	dir := a.Env.CompletionsDir()
	for _, rc := range a.completionRCFiles() {
		if stripMarkerLine(rc.path) == nil {
			a.Log.Info("已从 " + platform.ToSlash(rc.path) + " 移除补全配置")
		}
	}
	for _, name := range []string{"easywork.bash", "_easywork", "easywork.ps1"} {
		_ = os.Remove(filepath.Join(dir, name))
	}
	_ = os.Remove(dir)
	a.Log.Success("Shell 补全已移除")
	return 0
}

// completionStatus 打印补全安装状态。
func (a *App) completionStatus() int {
	dir := a.Env.CompletionsDir()
	out := a.Log.Out
	if a.JSON {
		out = a.Log.Err
	}
	writeLine := func(s string) { _, _ = out.Write([]byte(s + "\n")) }

	writeLine("补全文件目录: " + platform.ToSlash(dir))
	writeLine("")
	for _, f := range []struct{ shell, name string }{
		{"bash", "easywork.bash"}, {"zsh", "_easywork"}, {"pwsh", "easywork.ps1"},
	} {
		status := "(未安装)"
		if fileExists(filepath.Join(dir, f.name)) {
			status = platform.ToSlash(filepath.Join(dir, f.name)) + " ✓"
		}
		writeLine("  " + f.shell + ": " + status)
	}
	writeLine("")
	writeLine("已注入的 shell 配置文件:")
	found := false
	for _, rc := range a.completionRCFiles() {
		if rcHasCompletionMarker(rc.path) {
			writeLine("  " + rc.shell + ": " + platform.ToSlash(rc.path) + " ✓")
			found = true
		}
	}
	if !found {
		writeLine("  (无 — 运行 ew completion setup 安装补全)")
	}
	return 0
}

// cmdCompletion 分派 completion 子命令。
func (a *App) cmdCompletion(args []string) int {
	sub := "setup"
	if len(args) > 0 {
		sub = args[0]
	}
	switch sub {
	case "setup", "install":
		return a.setupCompletions()
	case "remove", "uninstall", "clean":
		return a.removeCompletions()
	case "status", "show":
		return a.completionStatus()
	default:
		return a.fail(1, "用法: ew completion <setup|remove|status>")
	}
}

func rcHasCompletionMarker(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(data), completionMarker)
}

// rcHasLine 报告文件中是否存在（除首尾空白外）与 line 完全相同的行。
func rcHasLine(path, line string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	want := strings.TrimSpace(line)
	for _, l := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(l) == want {
			return true
		}
	}
	return false
}

// stripMarkerLine 删除含补全标记的行（保留其余内容）。
func stripMarkerLine(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if !strings.Contains(string(data), completionMarker) {
		return nil
	}
	var out []string
	for _, l := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		if strings.Contains(l, completionMarker) {
			continue
		}
		out = append(out, l)
	}
	for len(out) > 0 && strings.TrimSpace(out[len(out)-1]) == "" {
		out = out[:len(out)-1]
	}
	content := ""
	if len(out) > 0 {
		content = strings.Join(out, "\n") + "\n"
	}
	return platform.AtomicWrite(path, []byte(content), 0o644)
}

// ─── 生成的补全脚本 ───────────────────────────────────────────

func bashCompletion(version, mods string) string {
	return `# EasyWork bash completion — generated by easywork ` + version + `
# DO NOT EDIT — regenerated on 'ew completion setup'

_easywork() {
    COMPREPLY=()
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    local global_opts="--yes -y --dry-run --verbose -v --json --offline"
    local uninstall_opts="--keep-config --remove-config"
    local commands="init install uninstall config version status list doctor update help completion keepawake"
    local modules="` + mods + `"

    local cmd=""
    local i
    for ((i = 1; i < COMP_CWORD; i++)); do
        [[ "${COMP_WORDS[i]}" != -* ]] && { cmd="${COMP_WORDS[i]}"; break; }
    done

    if [[ "$cur" == -* ]]; then
        local opts="$global_opts"
        [[ "$cmd" == "uninstall" ]] && opts="$opts $uninstall_opts"
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return
    fi

    if [[ -z "$cmd" ]]; then
        COMPREPLY=($(compgen -W "$commands $modules" -- "$cur"))
        return
    fi

    case "$cmd" in
        install | uninstall) COMPREPLY=($(compgen -W "$modules" -- "$cur")) ;;
        config)              COMPREPLY=($(compgen -W "edit show get set" -- "$cur")) ;;
        completion)          COMPREPLY=($(compgen -W "setup remove status" -- "$cur")) ;;
    esac
}
complete -F _easywork easywork
complete -F _easywork ew
`
}

func zshCompletion(version, mods string) string {
	return `#compdef easywork
# EasyWork zsh completion — generated by easywork ` + version + `
# DO NOT EDIT — regenerated on 'ew completion setup'

_easywork() {
    local -a cmds modules
    cmds=(init install uninstall config version status list doctor update help completion)
    modules=(` + mods + `)

    _arguments -C \
        '--yes[跳过交互确认]' \
        '-y[跳过交互确认]' \
        '--dry-run[预览变更不执行]' \
        '--verbose[详细输出]' \
        '-v[详细输出]' \
        '--json[机器可读 JSON]' \
        '--offline[禁止联网]' \
        '--keep-config[卸载时保留配置文件]' \
        '--remove-config[卸载时删除配置文件]' \
        "1:命令:($cmds $modules)" \
        '*::参数:->args'

    case "$state" in
        args)
            case "${line[1]}" in
                install | uninstall) compadd $modules ;;
                config)              compadd edit show get set ;;
                completion)          compadd setup remove status ;;
            esac
            ;;
    esac
}

if typeset -f compdef > /dev/null 2>&1; then
    compdef _easywork easywork
    compdef _easywork ew
fi
`
}

func pwshCompletion(version, mods string) string {
	return `# EasyWork PowerShell completion — generated by easywork ` + version + `
# DO NOT EDIT — regenerated on 'ew completion setup'

$__ew_modules = '` + mods + `' -split ' '
$__ew_commands = @('init','install','uninstall','config','version','status','list','doctor','update','help','completion')
$__ew_flags = @('--json','--dry-run','--yes','-y','--verbose','-v','--offline','--keep-config','--remove-config')

Register-ArgumentCompleter -Native -CommandName ew,easywork -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $tokens = $commandAst.CommandElements | ForEach-Object { $_.ToString() }
    $cmd = $tokens | Where-Object { $_ -notlike '-*' } | Select-Object -Skip 1 -First 1
    $candidates = @()
    if ($wordToComplete -like '-*') {
        $candidates = $__ew_flags
    } elseif (-not $cmd) {
        $candidates = $__ew_commands + $__ew_modules
    } elseif ($cmd -in @('install','uninstall')) {
        $candidates = $__ew_modules
    } elseif ($cmd -eq 'config') {
        $candidates = @('edit','show','get','set')
    } elseif ($cmd -eq 'completion') {
        $candidates = @('setup','remove','status')
    }
    $candidates | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
`
}
