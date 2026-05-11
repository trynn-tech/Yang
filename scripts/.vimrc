" =============================================================================
" 1. PLUGINS (Vim-Plug)
" =============================================================================
call plug#begin('~/.vim/plugged')
  Plug 'vimwiki/vimwiki'     " The structure for your Yang Wiki
  Plug 'tbabej/taskwiki'     " The engine connecting TW to your Wiki
  Plug 'powerman/vim-plugin-AnsiEsc' " Fixes color codes in viewports
call plug#end()

" =============================================================================
" 2. CORE SETTINGS
" =============================================================================
set nocompatible
filetype plugin indent on
syntax on
set encoding=utf-8
set noswapfile           " Crucial for performance on Android/Flash storage
set hidden               " Allow switching buffers without saving
set autoindent
set backspace=indent,eol,start

" Set <leader> key to Space (easier for mobile/desktop transition)
let mapleader = " "

" =============================================================================
" 3. VIMWIKI & TASKWIKI CONFIGURATION
" =============================================================================
" Path to your Yang Repo Wiki
let g:vimwiki_list = [{'path': '~/yang_wiki/', 'syntax': 'markdown', 'ext': '.md'}]

" Taskwiki Stability Fixes (Prevents the Traceback Crashes)
let g:taskwiki_taskbin = 'task'
let g:taskwiki_dont_preserve_environment = 1
let g:taskwiki_source_tw_colors = 0          " Disables color sync (fixes Python errors)
let g:taskwiki_extra_pythonpath = '~/.vim/plugged/taskwiki'

" Disable 'Live' sync to prevent crashing while typing
let g:taskwiki_disable_automatic_events = ['TextChanged', 'TextChangedI', 'InsertLeave']

" =============================================================================
" 4. SMART SYNC FUNCTION (The Logic)
" =============================================================================
" =============================================================================
function! YangSync()
    " Only run if we are in a Vimwiki file
    if &ft != 'vimwiki' | return | endif
    
    let l:save = winsaveview()
    silent! update
    
    " Check for the specific Taskwiki command
    if exists(':TaskWikiBufferUpdate')
        " Use 'silent!' to prevent the command from throwing pop-up errors
        silent! TaskWikiBufferUpdate
    endif
    
    call winrestview(l:save)
endfunction

" --- The Trigger ---
" Using 'BufWritePost' is safer than 'BufRead' to avoid the Ambiguous error on startup
augroup YangSyncGroup
    autocmd!
    autocmd BufWritePost ~/yang_wiki/*.md call YangSync()
augroup END

" 5. KEYBINDINGS (Speed Dial)
" =============================================================================
" Manual Refresh of Viewports
nnoremap <leader>tw :call YangSync()<CR>

" Taskwiki Shortcuts (Standardized)
" <leader>td -> Mark task as DONE
" <leader>ta -> Annotate task
" <leader>tr -> Refresh current line

" Use 'tt' for Task Toggle (Start/Stop) to avoid collision with Summary
nnoremap <leader>tt :!task %:t:r start<CR>:TaskWikiBufferUpdate<CR>
nnoremap <leader>th :!task %:t:r stop<CR>:TaskWikiBufferUpdate<CR>

" Use 'tx' for Task Delete
nnoremap <leader>tx :TaskWikiDelete<CR>



" Navigation
nnoremap <leader>ww :VimwikiIndex<CR>
nnoremap <leader>wt :VimwikiTabIndex<CR>

" Global Report Hotkey (Runs our bash alias from within Vim)
nnoremap <leader>r :!report<CR>
nnoremap <leader>cx :!task context none<CR>

" =============================================================================
" 6. FINAL HYGIENE
" =============================================================================
" Ensure markdown headers look distinct
highlight VimwikiHeader1 guifg=#FF5555 gui=bold
highlight VimwikiHeader2 guifg=#50FA7B gui=bold

" This tells Taskwiki: If it's [X], and it's not in the filter (+READY), delete the line.
let g:taskwiki_preserve_completed_tasks = 0

let g:vimwiki_file_exts = ['ledger', 'txt', 'pdf']
