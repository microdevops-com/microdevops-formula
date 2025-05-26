vim:
  managed_vimrc: true
  allow_localrc: false
  config:
    syntax: 'on'
    colors: koehler
    filetype: indent plugin on
    autocmd FileType yaml: setlocal ts=2 sts=2 sw=2 expandtab
    autocmd FileType yml: setlocal ts=2 sts=2 sw=2 expandtab
    autocmd FileType jinja: setlocal ts=2 sts=2 sw=2 expandtab
    autocmd FileType sls: setlocal ts=2 sts=2 sw=2 expandtab
  settings:
    hlsearch:
    nocompatible:
    ru:
    bs: indent,eol,start
    showcmd:
    showmatch:
    smartcase:
    incsearch:
    hidden:
    noerrorbells:
    novisualbell:
    #cin:
    #ai:
    #si:
    #cindent:
    tabstop: 8
    softtabstop: 8
    shiftwidth: 8
    nowrap:
    mouse: ""
