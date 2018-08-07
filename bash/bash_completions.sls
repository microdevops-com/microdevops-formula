# salt: https://raw.githubusercontent.com/saltstack/salt/develop/pkg/salt.bash

bash-completion:
  pkg.installed

virsh_bash_completion:
  file.managed:
    - name: '/etc/bash_completion.d/virsh'
    - source: 'salt://bash/files/virsh'

virsh_bash_completion:
  file.managed:
    - name: '/etc/bash_completion.d/salt'
    - source: 'salt://bash/files/salt'
