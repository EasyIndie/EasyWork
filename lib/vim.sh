#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# EasyWork — Vim IDE Configuration Module
# Installs Node.js, ripgrep, vim-plug, and generates ~/.vimrc with plugins.

MODULE_NAME="vim"
MODULE_DESCRIPTION="配置 Vim IDE"
MODULE_PRIORITY=30

VIMRC_FILE="$HOME/.vimrc"
VIM_DIR="$HOME/.vim"

# Declarative file target for the engine
MODULE_DECLARE=(
    "$VIMRC_FILE|_generate_vimrc|\"|vimrc_backup"
)

module_check() {
    [[ -f "$VIMRC_FILE" ]] && grep -qF "EasyWork managed section" "$VIMRC_FILE" 2> /dev/null
}

module_status() {
    if module_check; then
        echo "vim: 已安装 — ${VIMRC_FILE}"
    else
        echo "vim: 未安装"
    fi
}

# ─── Internal: Install Node.js ────────────────────────────────
_ensure_node() {
    if has_cmd node; then
        log_info "Node.js 已安装: $(node -v)"
        return 0
    fi

    log_info "安装 Node.js..."
    local os_type
    os_type="$(detect_os)"

    if [[ "$os_type" == "macos" ]] && has_cmd brew; then
        brew install node 2> /dev/null && return 0
        log_info "Homebrew 安装失败，尝试 nvm..."
    fi

    # Fallback: nvm
    export NVM_DIR="$HOME/.nvm"
    if [[ ! -d "$NVM_DIR" ]]; then
        safe_download "https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh" | bash 2> /dev/null || {
            log_warn "nvm 下载失败"
            return 1
        }
    fi
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        nvm install --lts 2> /dev/null || {
            log_warn "nvm install 失败"
            return 1
        }
        nvm alias default 'lts/*' 2> /dev/null || true
    fi

    if has_cmd node; then
        log_success "Node.js: $(node -v)"
        return 0
    fi
    log_warn "Node.js 安装失败，coc.nvim 和 markdown-preview 可能不可用"
    return 1
}

# ─── Internal: Install ripgrep ────────────────────────────────
_ensure_ripgrep() {
    if has_cmd rg; then
        log_info "ripgrep 已安装: $(rg --version 2> /dev/null | head -1)"
        return 0
    fi

    log_info "安装 ripgrep..."
    local pkg
    pkg="$(detect_pkg_manager)"

    case "$pkg" in
        brew) brew install ripgrep 2> /dev/null ;;
        apt-get) sudo apt-get update -y && sudo apt-get install -y ripgrep 2> /dev/null ;;
        dnf) sudo dnf install -y ripgrep 2> /dev/null ;;
        yum) sudo yum install -y ripgrep 2> /dev/null ;;
        pacman) sudo pacman -S --noconfirm ripgrep 2> /dev/null ;;
        zypper) sudo zypper install -y ripgrep 2> /dev/null ;;
        apk) sudo apk add ripgrep 2> /dev/null ;;
        *)
            if has_cmd cargo; then
                cargo install ripgrep 2> /dev/null && export PATH="$HOME/.cargo/bin:$PATH"
            fi
            ;;
    esac

    if has_cmd rg; then
        log_success "ripgrep: $(rg --version 2> /dev/null | head -1)"
        return 0
    fi
    log_warn "ripgrep 安装失败，FZF :Rg 命令不可用"
    return 1
}

# ─── Internal: Install vim-plug ───────────────────────────────
_ensure_vim_plug() {
    local plug_file="$VIM_DIR/autoload/plug.vim"
    if [[ -f "$plug_file" ]]; then
        log_info "vim-plug 已安装"
        return 0
    fi

    log_info "安装 vim-plug..."
    mkdir -p "$(dirname "$plug_file")"
    safe_download "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
        "$plug_file" 2> /dev/null || {
        log_warn "vim-plug 下载失败"
        return 1
    }
    log_success "vim-plug 安装完成"
    return 0
}

# ─── Internal: Generate Vim Config ────────────────────────────
_generate_vimrc() {
    cat << 'VIMRC'

" ── Basic Editing Experience ──
set backspace=indent,eol,start
set encoding=utf-8

" ── Backup / Swap / Undo ──
set nobackup
set noswapfile
set undofile
set undodir=~/.vim/undo

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
set clipboard=unnamedplus
set mouse=a
set termguicolors
set signcolumn=yes

" ── Theme ──
syntax enable
set background=dark
colorscheme murphy

" ── Plugin Manager: vim-plug ──
call plug#begin('~/.vim/plugged')

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
let g:NERDTreeGitStatusIndicatorMapCustom = {
    \ 'Modified'  : '✹',
    \ 'Staged'    : '✚',
    \ 'Untracked' : '✭',
    \ 'Renamed'   : '➜',
    \ 'Unmerged'  : '═',
    \ 'Deleted'   : '✖',
    \ 'Dirty'     : '✗',
    \ 'Clean'     : '✔︎',
    \ 'Ignored'   : '☒',
    \ 'Unknown'   : '?'
    \ }

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
VIMRC
}

# ─── Module: Install ──────────────────────────────────────────
module_install() {
    if ! has_cmd curl; then
        log_error "curl 未安装"
        return $EXIT_MISSING_DEPS
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将安装 Node.js（如需要）"
        log_info "[DRY-RUN] 将安装 ripgrep（如需要）"
        log_info "[DRY-RUN] 将安装 vim-plug"
        log_info "[DRY-RUN] 将生成/更新: $VIMRC_FILE"
        return 0
    fi

    # Install dependencies
    _ensure_node || log_warn "Node.js 不可用，部分插件可能不工作"
    _ensure_ripgrep || true
    _ensure_vim_plug || {
        log_error "vim-plug 安装失败"
        return $EXIT_ERROR
    }

    # Backup existing vimrc + write managed section (via engine)
    local vimrc_backup=""
    apply_module_files || return $EXIT_ERROR
    if [[ -n "$vimrc_backup" ]]; then
        log_info "已备份现有 ~/.vimrc → ${vimrc_backup}"
    fi
    log_success "已生成: $VIMRC_FILE"

    # Create undo directory
    mkdir -p "$VIM_DIR/undo" 2> /dev/null || true

    # Install vim plugins
    if has_cmd vim; then
        log_info "安装 Vim 插件..."
        # Suppress vim errors during headless plugin install
        vim +PlugClean! +qall 2> /dev/null || true
        vim +PlugInstall +qall 2> /dev/null || true
        log_success "Vim 插件安装完成"
    else
        log_warn "未找到 vim，请手动运行 :PlugInstall 安装插件"
    fi

    # Record to manifest
    manifest_set_section "vim" \
        "installed=true" \
        "vimrc_file=${VIMRC_FILE}" \
        "${vimrc_backup:+vimrc_backup=${vimrc_backup}}" \
        "plug_dir_created=${VIM_DIR}"

    log_success "Vim IDE 配置完成 ✓"
    return 0
}

# ─── Module: Uninstall ────────────────────────────────────────
module_uninstall() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] 将恢复备份的 ~/.vimrc（如有）"
        log_info "[DRY-RUN] 将询问是否删除 ~/.vim 目录"
        return 0
    fi

    # Restore backup or remove managed section
    local bak_file
    bak_file="$(manifest_read_section_key 'vim' 'vimrc_backup' '')"
    if [[ -n "$bak_file" ]] && [[ -f "$bak_file" ]]; then
        local answer="y"
        if [[ "${YES_MODE:-false}" != "true" ]]; then
            read -r -p "  恢复备份的 ~/.vimrc？[Y/n] " answer
        fi
        if [[ ! "$answer" =~ ^[Nn] ]]; then
            remove_managed_file "$VIMRC_FILE" "$bak_file"
            log_success "已恢复备份的 ~/.vimrc"
        fi
    else
        if [[ -f "$VIMRC_FILE" ]] && grep -qF "EasyWork managed section" "$VIMRC_FILE" 2> /dev/null; then
            remove_managed_file "$VIMRC_FILE" ""
            log_success "已移除 EasyWork Vim 配置"
        fi
    fi

    # Ask about ~/.vim directory
    if [[ -d "$VIM_DIR" ]]; then
        local answer="y"
        if [[ "${YES_MODE:-false}" != "true" ]]; then
            read -r -p "  删除 ~/.vim 目录（含所有插件）？[Y/n] " answer
        fi
        if [[ ! "$answer" =~ ^[Nn] ]]; then
            # Safety check: ensure we're deleting the right directory
            if [[ "$VIM_DIR" == "$HOME/.vim" ]] && [[ "$VIM_DIR" != "/" ]]; then
                rm -rf "$VIM_DIR"
                log_success "已删除: $VIM_DIR"
            else
                log_warn "路径异常，跳过删除: $VIM_DIR"
            fi
        else
            log_info "保留: $VIM_DIR"
        fi
    fi

    return 0
}
