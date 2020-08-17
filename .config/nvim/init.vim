call plug#begin()
Plug 'tpope/vim-rails'
Plug 'thoughtbot/vim-rspec'
Plug 'tpope/vim-bundler'
Plug 'tpope/vim-fugitive'
Plug 'vim-ruby/vim-ruby'
Plug 'tpope/vim-commentary'
Plug 'vim-airline/vim-airline'
Plug 'rbgrouleff/bclose.vim'
Plug 'jeetsukumaran/vim-buffergator'
Plug 'tpope/vim-dispatch'
Plug 'ngmy/vim-rubocop'
Plug 'tpope/vim-surround'
Plug 'dense-analysis/ale'
Plug 'altercation/vim-colors-solarized', { 'dir': '~/.config/nvim/colors/solarized' }
Plug 'lifepillar/vim-solarized8', { 'dir': '~/.config/nvim/colors/solarized8' }
Plug 'sonph/onehalf', { 'dir': '~/.config/nvim/colors/onehalf' }
Plug 'vim-airline/vim-airline-themes'
Plug 'preservim/nerdtree'
Plug 'scrooloose/nerdtree'
Plug 'autozimu/LanguageClient-neovim', {
    \ 'branch': 'next',
    \ 'do': 'bash install.sh',
    \ }
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'cakebaker/scss-syntax.vim'
Plug 'mustache/vim-mustache-handlebars'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'kevinoid/vim-jsonc'
Plug 'tpope/vim-rake'
Plug 'pangloss/vim-javascript'
Plug 'mrk21/yaml-vim'
Plug 'noprompt/vim-yardoc'
Plug 'benmills/vimux'
Plug 'vim-test/vim-test'
call plug#end()

let g:run_rspec_bin = 'bundle exec rspec'

let g:airline_theme='solarized'

" important!!
set number
set smarttab
set cindent
"set listchars=eol:$,nbsp:_,tab:>-,trail:~,extends:>,precedes:<,space:.
"set list

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)


"set termguicolors
let g:solarized_use16=1
set background=dark
syntax enable
colorscheme solarized8
let g:rspec_command = "Dispatch rspec -c {spec}"

let g:ale_linters = {
			\ "ruby": [
			\	"rubocop"
			\]
			\}

let g:ale_fixers = {
                     \ "ruby": ["rubocop"],
                     \ "css": ["prettier"],
                     \ "erb": ["prettier"],
                     \ "scss": ["prettier"],
                     \ "javascript": ["prettier"]
                \ }
let g:ale_fix_on_save = 1
map <a-f> :FZF<CR>

autocmd FileType ruby setlocal omnifunc=LanguageClient#complete

let sw=2

" RSpec.vim mappings
map <Leader>t :call RunCurrentSpecFile()<CR>
map <Leader>s :call RunNearestSpec()<CR>
map <Leader>l :call RunLastSpec()<CR>
map <Leader>a :call RunAllSpecs()<CR>
map <Leader><tab> :Commentary<Cr>
map <Leader>f :w<CR>:RuboCop -a<CR>q
map <a-[> :tabp<CR>
map <a-]> :tabn<CR>
map <a-c> :CtrlPClearCache<cr>

:nnoremap <leader><leader> :NERDTree<CR>
:nnoremap <leader>q :NERDTreeClose<CR>:CtrlPClearCache<CR>
let g:ale_sign_column_always = 1
set tabstop=2

autocmd FileType javascript setlocal shiftwidth=2 tabstop=2
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab indentkeys-=0# indentkeys-=<:> foldmethod=indent nofoldenable

fun! SetupCommandAlias(from, to)
  exec 'cnoreabbrev <expr> '.a:from
        \ .' ((getcmdtype() is# ":" && getcmdline() is# "'.a:from.'")'
        \ .'? ("'.a:to.'") : ("'.a:from.'"))'
endfun
call SetupCommandAlias("W","w")

let test#strategy = "vimux"
nmap <silent> t<C-n> :TestNearest<CR>
nmap <silent> t<C-f> :TestFile<CR>
nmap <silent> t<C-s> :TestSuite<CR>
nmap <silent> t<C-l> :TestLast<CR>
nmap <silent> t<C-g> :TestVisit<CR>
