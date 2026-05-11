#!/data/data/com.termux/files/usr/bin/bash

echo "  =^-.-^=  "
echo " Initializing ... Yang ..."

# 1. System Dependencies
pkg update && pkg upgrade -y
pkg install -y vim python git taskwarrior curl

# 2. Python Bridge
pip install tasklib

# 3. Setup Vim-Plug
if [ ! -f ~/.vim/autoload/plug.vim ]; then
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# 4. Deploy .taskrc (The Vectorization Logic)
cat << 'EOF' > ~/.taskrc
# -----------------------------------------------------------------------------
# TODO: SERVER CUSTOMIZATION
# Replace the IP/Port and Credentials with your specific server details.
# -----------------------------------------------------------------------------
taskd.server=100.64.55.98:8080
taskd.credentials=public/yuko/YOUR_UUID_HERE

# TODO: CERTIFICATES
# Ensure these paths point to where you store your .pem files
taskd.trust=allow all
taskd.certificate=~/.task/user.cert.pem
taskd.key=~/.task/user.key.pem
taskd.ca=~/.task/ca.cert.pem

# Stability for Mobile
confirmation=no
allow.empty.filter=yes
EOF

# 5. Deploy .vimrc
cat << 'EOF' > ~/.vimrc
call plug#begin('~/.vim/plugged')
  Plug 'vimwiki/vimwiki'
  Plug 'tbabej/taskwiki'
  Plug 'powerman/vim-plugin-AnsiEsc'
call plug#end()

" -----------------------------------------------------------------------------
" TODO: WIKI PATH
" Change '~/wiki_yuko/' if you move your vault (e.g., to /storage/emulated/0/...)
" -----------------------------------------------------------------------------
let g:vimwiki_list = [{'path': '~/wiki_yuko/', 'syntax': 'markdown', 'ext': '.md'}]

let g:taskwiki_taskbin = 'task'
let g:taskwiki_extra_pythonpath = '~/.vim/plugged/taskwiki'
let g:taskwiki_disable_automatic_events = 1

function! TaskSync()
    if &ft != 'vimwiki' | return | endif
    let l:save = winsaveview()
    silent update
    if exists('*taskwiki#BufferPull') | call taskwiki#BufferPull() | else | silent! python3 tw.buffer_read() | endif
    
    " Clean duplicates
    silent! %s/^\(\* \[ \].*#\w\+\)\n\n\1$/\1/e
    silent! %s/\(#\w\+\)\n\n/\1\r/e
    
    silent update
    call winrestview(l:save)
    redraw!
    echo "Honed & Synced."
endfunction

" Keybindings
autocmd FileType vimwiki nnoremap <buffer> tt :call TaskSync()<CR>
autocmd FileType vimwiki nnoremap <buffer> ts :call TaskSync()<CR>:!task sync<CR>
EOF

# 6. Finalize Plugins
vim +PlugInstall +qall

echo "✨ All set! Your configuration is now immortalized."
echo "Check the 'TODO' sections in ~/.taskrc and ~/.vimrc for personalization."


