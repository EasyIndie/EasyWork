package modules

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/EasyIndie/EasyWork/internal/engine"
	"github.com/EasyIndie/EasyWork/internal/platform"
)

type vimModule struct{}

func (vimModule) Name() string             { return "vim" }
func (vimModule) Description() string      { return "配置 Vim IDE" }
func (vimModule) Priority() int            { return 30 }
func (vimModule) Platforms() []platform.OS { return allPlatforms() }

// vimrcTemplate 中 {{UNDODIR}} / {{PLUGGED}} 由 vimrcContent 按平台替换。
const vimrcTemplate = `" ── Basic Editing ──
set backspace=indent,eol,start
set encoding=utf-8

" ── Backup / Swap / Undo ──
set nobackup
set noswapfile
set undofile
set undodir={{UNDODIR}}

" ── Line Numbers & Cursor ──
set number
set nowrap
set ruler
set cursorline

" ── Indentation ──
set cindent
set tabstop=4
set shiftwidth=4
set expandtab
set smartindent
set autoindent

" ── Search ──
set ignorecase
set smartcase
set hlsearch
set incsearch

" ── Display ──
set showmode
set nofoldenable
set splitbelow
set splitright
set mouse=a
set termguicolors
set signcolumn=yes

" ── Theme ──
syntax enable
set background=dark
colorscheme murphy

" ── Plugin Manager: vim-plug ──
call plug#begin('{{PLUGGED}}')

" File tree
Plug 'preservim/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'

" Status bar
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" Git
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'

" Comments
Plug 'tpope/vim-commentary'

" Markdown
Plug 'preservim/vim-markdown'
Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() } }

" HTML/CSS/Emmet
Plug 'mattn/emmet-vim'
Plug 'othree/html5.vim'
Plug 'hail2u/vim-css3-syntax'

" JavaScript/React
Plug 'pangloss/vim-javascript'
Plug 'maxmellon/vim-jsx-pretty'

" Linting (ALE)
Plug 'dense-analysis/ale'

" Fuzzy Search (FZF)
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

" Completion (coc.nvim — requires Node.js)
Plug 'neoclide/coc.nvim', {'branch': 'release'}

call plug#end()

" ── NERDTree ──
let NERDTreeShowHidden=1
nnoremap <C-n> :NERDTreeToggle<CR>
let g:NERDTreeGitStatusShowIgnored = 1

" ── Airline ──
let g:airline_theme='papercolor'

" ── ALE (Linting) ──
let g:ale_linters = { 'javascript': ['eslint'], 'css': ['stylelint'] }
let g:ale_fixers =  { 'javascript': ['eslint'], 'css': ['stylelint'] }
let g:ale_fix_on_save = 1
let g:ale_sign_column_always = 1
let g:ale_sign_error = '●'
let g:ale_sign_warning = '▶'
nmap <silent> <C-k> <Plug>(ale_previous_wrap)
nmap <silent> <C-j> <Plug>(ale_next_wrap)

" ── coc.nvim (LSP) ──
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gr <Plug>(coc-references)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> K :call CocAction('doHover')<CR>
inoremap <silent><expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr><S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" ── Markdown Preview ──
let mapleader=" "
let g:mkdp_auto_start=0
let g:mkdp_auto_close=1
nnoremap <silent> <leader>mp :MarkdownPreview<CR>
nnoremap <silent> <leader>ms :MarkdownPreviewStop<CR>
nnoremap <silent> <leader>mt :MarkdownPreviewToggle<CR>
`

const vimPlugURL = "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

// vimrcContent 生成平台相关的 vimrc（undo/plugged 目录随 Vim 运行时目录变化）。
func vimrcContent(env platform.Env) string {
	pluginDir := platform.ToSlash(env.VimPluginDir())
	r := strings.NewReplacer(
		"{{UNDODIR}}", pluginDir+"/undo",
		"{{PLUGGED}}", pluginDir+"/plugged",
	)
	return r.Replace(vimrcTemplate)
}

// ensureNode 保证 Node.js 可用（包管理器优先，Unix 回退 nvm）。
func ensureNode(ctx *Context) bool {
	if platform.HasCmd("node") {
		ctx.Log.Info("Node.js 已安装")
		return true
	}
	if ctx.Offline {
		ctx.Log.Warn("离线模式：跳过 Node.js 安装")
		return false
	}
	pm := platform.DetectPackageManager()
	if pm.Known() {
		ctx.Log.Info("使用 " + pm.Name() + " 安装 Node.js...")
		if err := pm.Install("node"); err == nil && platform.HasCmd("node") {
			ctx.Log.Success("Node.js 安装完成")
			return true
		}
	}
	if platform.DetectOS() != platform.Windows {
		// 回退 nvm：安装 nvm 后 `nvm install --lts`
		nvmSh := filepath.Join(ctx.Env.Home, ".nvm", "nvm.sh")
		if _, err := os.Stat(nvmSh); err != nil {
			installer := filepath.Join(ctx.Env.TempDir, "ew-nvm-install.sh")
			if err := platform.Download("https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh", installer); err == nil {
				_ = exec.Command("bash", installer).Run()
			}
		}
		if _, err := os.Stat(nvmSh); err == nil {
			cmd := exec.Command("bash", "-lc", `source "$HOME/.nvm/nvm.sh" && nvm install --lts`)
			cmd.Env = append(os.Environ(), "NVM_DIR="+filepath.Join(ctx.Env.Home, ".nvm"))
			if err := cmd.Run(); err == nil {
				ctx.Log.Success("Node.js 安装完成（nvm）")
				return true
			}
		}
	}
	ctx.Log.Warn("Node.js 不可用，部分插件可能不工作")
	return false
}

// ensureRipgrep 保证 ripgrep 可用（包管理器优先，回退 cargo）。
func ensureRipgrep(ctx *Context) bool {
	if platform.HasCmd("rg") {
		ctx.Log.Info("ripgrep 已安装")
		return true
	}
	if ctx.Offline {
		ctx.Log.Warn("离线模式：跳过 ripgrep 安装")
		return false
	}
	if pm := platform.DetectPackageManager(); pm.Known() {
		ctx.Log.Info("使用 " + pm.Name() + " 安装 ripgrep...")
		if err := pm.Install("ripgrep"); err == nil && platform.HasCmd("rg") {
			ctx.Log.Success("ripgrep 安装完成")
			return true
		}
	}
	if platform.HasCmd("cargo") {
		if err := exec.Command("cargo", "install", "ripgrep").Run(); err == nil && platform.HasCmd("rg") {
			ctx.Log.Success("ripgrep 安装完成（cargo）")
			return true
		}
	}
	ctx.Log.Warn("ripgrep 安装失败，FZF :Rg 命令不可用")
	return false
}

func (vimModule) Install(ctx *Context) error {
	target := ctx.Env.VimConfigPath()
	plug := ctx.Env.VimPlugPath()

	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将安装 Node.js（如需要）")
		ctx.Log.Info("[DRY-RUN] 将安装 ripgrep（如需要）")
		ctx.Log.Info("[DRY-RUN] 将安装 vim-plug")
		ctx.Log.Info("[DRY-RUN] 将生成/更新: " + target)
		ctx.Log.Info("[DRY-RUN] 将运行 :PlugInstall")
		return nil
	}

	ensureNode(ctx)
	ensureRipgrep(ctx)

	// vim-plug
	if _, statErr := os.Stat(plug); statErr != nil {
		if ctx.Offline {
			ctx.Log.Warn("离线模式：跳过 vim-plug 安装")
		} else if err := platform.Download(vimPlugURL, plug); err != nil {
			ctx.Log.Error("vim-plug 下载失败")
			return err
		} else {
			ctx.Log.Success("vim-plug 安装完成")
		}
	}

	backup, err := engine.ApplyManagedSection(target, ctx.Version, vimrcContent(ctx.Env), `"`)
	if err != nil {
		return err
	}
	ctx.Log.Success("已生成: " + target)

	// undo / plugged 目录
	_ = os.MkdirAll(filepath.Join(ctx.Env.VimPluginDir(), "undo"), 0o755)
	_ = os.MkdirAll(filepath.Join(ctx.Env.VimPluginDir(), "plugged"), 0o755)

	// 安装插件（需联网）
	if platform.HasCmd("vim") && !ctx.Offline {
		ctx.Log.Info("安装 Vim 插件...")
		_ = exec.Command("vim", "+PlugClean!", "+qall").Run()
		if err := exec.Command("vim", "+PlugInstall", "+qall").Run(); err != nil {
			ctx.Log.Warn("部分插件安装失败，可稍后在 Vim 内运行 :PlugInstall")
		} else {
			ctx.Log.Success("Vim 插件安装完成")
		}
	} else if !platform.HasCmd("vim") {
		ctx.Log.Warn("未找到 vim，请手动运行 :PlugInstall 安装插件")
	}

	pairs := []string{"installed=true", "vimrc_file=" + target, "plug_dir_created=" + ctx.Env.VimPluginDir()}
	if backup != "" {
		pairs = append(pairs, "vimrc_backup="+backup)
	}
	return ctx.Manifest.SetSection("vim", pairs...)
}

func (vimModule) Uninstall(ctx *Context) error {
	if ctx.DryRun {
		ctx.Log.Info("[DRY-RUN] 将移除 Vim 配置")
		return nil
	}
	target := ctx.Env.VimConfigPath()
	backup := ctx.Manifest.ReadSectionKey("vim", "vimrc_backup", "")
	return engine.RemoveFile(target, backup)
}
