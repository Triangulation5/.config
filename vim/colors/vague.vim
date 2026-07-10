" Name:         vague
" Description:  A cool, dark, low contrast colorscheme. Pastel yet vivid, like a fleeting memory... 
" Maintainer:   Artem Krinitsyn <arkriny@gmail.com>
" URL:          https://github.com/vague-theme/vague.vim
" License:      MIT

set background=dark
hi clear
if exists('syntax on')
    syntax reset
endif
let g:colors_name='vague'

let g:terminal_ansi_colors = ['#252530', '#d8647e', '#7fa563', '#f3be7c', '#6e94b2', '#bb9dbd', '#aeaed1', '#cdcdcd', '#606079', '#e08398', '#99b782', '#f5cb96', '#8ba9c1', '#c9b1ca', '#bebeda', '#d7d7d7']

if !(has('termguicolors') && &termguicolors) && !has('gui_running') && &t_Co != 256
  finish " Only gui is supported
endif

hi Added cterm=NONE gui=NONE guifg=#7fa563 guibg=NONE guisp=NONE
hi Boolean cterm=bold gui=bold guifg=#e0a363 guibg=NONE guisp=NONE
hi Changed cterm=NONE gui=NONE guifg=#f3be7c guibg=NONE guisp=NONE
hi Character cterm=NONE gui=NONE guifg=#e8b589 guibg=NONE guisp=NONE
hi ColorColumn cterm=NONE gui=NONE guifg=NONE guibg=#252530 guisp=NONE
hi Comment cterm=italic gui=italic guifg=#606079 guibg=NONE guisp=NONE
hi Conceal cterm=NONE gui=NONE guifg=#c48282 guibg=NONE guisp=NONE
hi Constant cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi CursorColumn cterm=NONE gui=NONE guifg=NONE guibg=#252530 guisp=NONE
hi CursorLine cterm=NONE gui=NONE guifg=NONE guibg=#252530 guisp=NONE
hi CursorLineNr cterm=NONE gui=NONE guifg=#cdcdcd guibg=NONE guisp=NONE
hi Debug cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi Delimiter cterm=NONE gui=NONE guifg=#cdcdcd guibg=NONE guisp=NONE
hi DiffAdd cterm=NONE gui=NONE guifg=NONE guibg=#293125 guisp=NONE
hi DiffChange cterm=NONE gui=NONE guifg=NONE guibg=#41362a guisp=NONE
hi DiffDelete cterm=NONE gui=NONE guifg=NONE guibg=#3b242a guisp=NONE
hi DiffText cterm=NONE gui=NONE guifg=NONE guibg=#6d583e guisp=NONE
hi Directory cterm=NONE gui=NONE guifg=#7e98e8 guibg=NONE guisp=NONE
hi Error cterm=bold gui=bold guifg=NONE guibg=#d8647e guisp=NONE
hi ErrorMsg cterm=bold gui=bold guifg=#d8647e guibg=NONE guisp=NONE
hi FoldColumn cterm=NONE gui=NONE guifg=#606079 guibg=NONE guisp=NONE
hi Folded cterm=NONE gui=NONE guifg=#606079 guibg=#252530 guisp=NONE
hi Function cterm=NONE gui=NONE guifg=#c48282 guibg=NONE guisp=NONE
hi Identifier cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi Ignore cterm=NONE gui=NONE guifg=#cdcdcd guibg=#141415 guisp=NONE
hi IncSearch cterm=NONE gui=NONE guifg=#141415 guibg=#405065 guisp=NONE
hi Include cterm=NONE gui=NONE guifg=#6e94b2 guibg=NONE guisp=NONE
hi LineNr cterm=NONE gui=NONE guifg=#606079 guibg=NONE guisp=NONE
hi MatchParen cterm=bold gui=bold guifg=NONE guibg=#333738 guisp=NONE
hi ModeMsg cterm=NONE gui=NONE guifg=#e8b589 guibg=NONE guisp=NONE
hi MoreMsg cterm=bold gui=bold guifg=#c48282 guibg=NONE guisp=NONE
hi NonText cterm=NONE gui=NONE guifg=#606079 guibg=NONE guisp=NONE
hi Normal cterm=NONE gui=NONE guifg=#cdcdcd guibg=#141415 guisp=NONE
hi Number cterm=NONE gui=NONE guifg=#e0a363 guibg=NONE guisp=NONE
hi Operator cterm=NONE gui=NONE guifg=#90a0b5 guibg=NONE guisp=NONE
hi Pmenu cterm=NONE gui=NONE guifg=#cdcdcd guibg=#252530 guisp=NONE
hi PmenuSbar cterm=NONE gui=NONE guifg=#cdcdcd guibg=#252530 guisp=NONE
hi PmenuSel cterm=NONE gui=NONE guifg=#252530 guibg=#cdcdcd guisp=NONE
hi PmenuShadow cterm=NONE gui=NONE guifg=NONE guibg=#333738 guisp=NONE
hi PmenuThumb cterm=NONE gui=NONE guifg=NONE guibg=#606079 guisp=NONE
hi PreProc cterm=NONE gui=NONE guifg=#6e94b2 guibg=NONE guisp=NONE
hi Question cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi QuickFixLine cterm=NONE gui=NONE guifg=NONE guibg=#1c1c24 guisp=NONE
hi Removed cterm=NONE gui=NONE guifg=#d8647e guibg=NONE guisp=NONE
hi Search cterm=NONE gui=NONE guifg=#cdcdcd guibg=#405065 guisp=NONE
hi SignColumn cterm=NONE gui=NONE guifg=#cdcdcd guibg=NONE guisp=NONE
hi Special cterm=NONE gui=NONE guifg=#b4d4cf guibg=NONE guisp=NONE
hi SpecialChar cterm=NONE gui=NONE guifg=#6e94b2 guibg=NONE guisp=NONE
hi SpecialComment cterm=NONE gui=NONE guifg=#6e94b2 guibg=NONE guisp=NONE
hi SpecialKey cterm=NONE gui=NONE guifg=#606079 guibg=NONE guisp=NONE
hi SpellBad cterm=undercurl gui=undercurl guifg=NONE guibg=NONE guisp=#d8647e
hi SpellCap cterm=undercurl gui=undercurl guifg=NONE guibg=NONE guisp=#f3be7c
hi SpellLocal cterm=undercurl gui=undercurl guifg=NONE guibg=NONE guisp=#7e98e8
hi SpellRare cterm=undercurl gui=undercurl guifg=NONE guibg=NONE guisp=#aeaed1
hi Statement cterm=NONE gui=NONE guifg=#6e94b2 guibg=NONE guisp=NONE
hi StatusLine cterm=NONE gui=NONE guifg=#cdcdcd guibg=#1c1c24 guisp=NONE
hi StatusLineNC cterm=NONE gui=NONE guifg=#606079 guibg=NONE guisp=NONE
hi StatusLineTerm cterm=NONE gui=NONE guifg=#cdcdcd guibg=#1c1c24 guisp=NONE
hi StatusLineTermNC cterm=NONE gui=NONE guifg=#606079 guibg=NONE guisp=NONE
hi StorageClass cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi String cterm=italic gui=italic guifg=#e8b589 guibg=NONE guisp=NONE
hi Structure cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi TabLine cterm=NONE gui=NONE guifg=#606079 guibg=#1c1c24 guisp=NONE
hi TabLineFill cterm=NONE gui=NONE guifg=#606079 guibg=#1c1c24 guisp=NONE
hi Title cterm=NONE gui=NONE guifg=#c3c3d5 guibg=NONE guisp=NONE
hi Todo cterm=italic gui=italic guifg=#c48282 guibg=NONE guisp=NONE
hi Type cterm=NONE gui=NONE guifg=#9bb4bc guibg=NONE guisp=NONE
hi TypeDef cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi Underlined cterm=underline gui=underline guifg=NONE guibg=NONE guisp=NONE
hi VertSplit cterm=NONE gui=NONE guifg=#878787 guibg=NONE guisp=NONE
hi Visual cterm=NONE gui=NONE guifg=NONE guibg=#333738 guisp=NONE
hi VisualNOS cterm=underline gui=underline guifg=NONE guibg=#606079 guisp=NONE
hi WarningMsg cterm=bold gui=bold guifg=#f3be7c guibg=NONE guisp=NONE
hi WildMenu cterm=NONE gui=NONE guifg=#141415 guibg=#c48282 guisp=NONE
hi htmlArg cterm=NONE gui=NONE guifg=#aeaed1 guibg=NONE guisp=NONE
hi htmlEndTag cterm=NONE gui=NONE guifg=#cdcdcd guibg=NONE guisp=NONE
hi htmlSpecialTagName cterm=NONE gui=NONE guifg=#b4d4cf guibg=NONE guisp=NONE
hi htmlTag cterm=NONE gui=NONE guifg=#cdcdcd guibg=NONE guisp=NONE
hi htmlTagName cterm=NONE gui=NONE guifg=#b4d4cf guibg=NONE guisp=NONE
