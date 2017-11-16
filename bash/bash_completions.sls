bash-completion:
  pkg.installed

virsh_bash_completion:
  file.managed:
    - name: '/etc/bash_completion.d/virsh'
    - source: 'salt://bash/files/virsh'
