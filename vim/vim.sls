include:
  - vim
  - vim.salt
  - vim.nerdtree

# vim-tiny turns on compatibility mode and nothing cool works
vim-tiny:
  pkg.purged

vim_custom_syntax_files:
  file.recurse:
    - name: '/usr/share/vim/vimfiles'
    - source: 'salt://vim/vimfiles'
    - user: 'root'
    - group: 'root'
    - dir_mode: 755
    - file_mode: 644

vim_rewrite_default_editor:
  cmd.run:
    - name: 'if [ -f /etc/alternatives/editor ] ; then _vim_bin=$(which vim.basic) && update-alternatives --set editor ${_vim_bin} ; else exit 0 ; fi'
    - runas: 'root'
