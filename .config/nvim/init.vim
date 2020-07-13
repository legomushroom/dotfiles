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
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'dense-analysis/ale'
Plug 'altercation/vim-colors-solarized', { 'dir': '~/.config/nvim/colors/solarized' }
Plug 'lifepillar/vim-solarized8', { 'dir': '~/.config/nvim/colors/solarized8' }
Plug 'sonph/onehalf', { 'dir': '~/.config/nvim/colors/onehalf' }
Plug 'vim-airline/vim-airline-themes'
Plug 'preservim/nerdtree'
Plug 'scrooloose/nerdtree'
Plug 'kien/ctrlp.vim'
Plug 'autozimu/LanguageClient-neovim', {
    \ 'branch': 'next',
    \ 'do': 'bash install.sh',
    \ }
Plug 'junegunn/fzf'
call plug#end()

let g:run_rspec_bin = 'bundle exec rspec'

let g:airline_theme='solarized'

" important!!
set number
"set listchars=eol:$,nbsp:_,tab:>-,trail:~,extends:>,precedes:<,space:.
"set list
let g:deoplete#enable_at_startup = 1

"set termguicolors
let g:solarized_use16=1
set background=dark
syntax enable
colorscheme solarized8

let g:LanguageClient_serverCommands = {
    \ 'ruby': ['~/.rbenv/shims/solargraph', 'stdio']
    \ }

let g:LanguageClient_autoStop = 0
let g:rspec_command = "Dispatch rspec -c {spec}"

let g:ale_linters = {
			\ "ruby": [
			\	"rubocop"
			\]
			\}
let g:ctrlp_map = '<a-f>'
let g:ctrlp_cmd = 'CtrlP'
autocmd FileType ruby setlocal omnifunc=LanguageClient#complete


let g:ctrlp_custom_ignore = 'node_modules\|DS_Store\|git'
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
