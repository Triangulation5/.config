set nocompatible

" --- plugin bootstrap ---
if empty(glob(expand('~/.vim/autoload/plug.vim')))
  silent execute '!curl -fLo ' . expand('~/.vim/autoload/plug.vim') . ' --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * ++once PlugInstall | q
endif

call plug#begin('~/.vim/plugged')
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'neoclide/coc.nvim', { 'branch': 'release' }
call plug#end()

" --- UI / behavior ---
colorscheme retrobox
set number
set relativenumber
set numberwidth=4
set signcolumn=yes
set colorcolumn=80
set cursorline
set showmatch
set laststatus=2
set noshowmode
set title
set statusline=%f%m%r\ [%{&filetype}]\ %=%l:%c\ %p%%
set belloff=all

" --- encoding / syntax ---
set encoding=utf-8
syntax on
filetype plugin indent on

" --- tabs / indent ---
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set autoindent
set smartindent
set breakindent

" --- search ---
set ignorecase
set smartcase
set incsearch
set hlsearch
set nohlsearch

" --- scrolling ---
set scrolloff=8
set sidescrolloff=8

" --- timing ---
set updatetime=50
set timeoutlen=150

" --- misc ---
set backspace=indent,eol,start
set list
set listchars=tab:\ \ ,trail:·
set background=dark
set termguicolors
set noswapfile
set whichwrap+=<,>,[,],h,l
set iskeyword+=-
set completeopt=menuone,noselect

" --- netrw ---
let g:netrw_banner=0

" --- restore cursor ---
autocmd BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | exe "normal! g`\"" | endif

" --- leader ---
let mapleader=" "
let maplocalleader="\\"

" --- fzf ---
let $FZF_DEFAULT_COMMAND = "rg --files --hidden --follow --glob '!.git/*'"
let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.8 } }

nnoremap <C-p> :Files<CR>
nnoremap <leader>f :Files<CR>
nnoremap <leader>fg :Rg<CR>
nnoremap <leader>fb :Buffers<CR>
nnoremap <leader>h :Helptags<CR>
nnoremap <leader>e :Explore<CR>
nnoremap <leader>ef :Vexplore<CR>

" --- lsp (coc) ---
nnoremap gd <Plug>(coc-definition)
nnoremap gr <Plug>(coc-references)
nnoremap gi <Plug>(coc-implementation)

" --- basic mappings ---
nnoremap <leader>w :%s/\s\+$//e<CR>:w<CR>
nnoremap <leader>q :quit<CR>

nnoremap <leader>bn :bn<CR>
nnoremap <leader>bp :bp<CR>
nnoremap <leader>bd :bdelete<CR>
nnoremap <leader>bf :bw!<CR>

vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

nnoremap n nzzzv
nnoremap N Nzzzv

inoremap <C-h> <C-w>
inoremap <C-BS> <C-w>
inoremap jk <Esc>

nnoremap d "_d
vnoremap d "_d
nnoremap c "_c
vnoremap c "_c
nnoremap x "_x
