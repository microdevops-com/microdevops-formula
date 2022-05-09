# salt: https://raw.githubusercontent.com/saltstack/salt/develop/pkg/salt.bash

bash-completion_pkg:
  pkg.installed:
    - name: bash-completion

bash_completion_virsh:
  file.managed:
    - name: /etc/bash_completion.d/virsh
    - source: salt://bash/files/completions/virsh

bash_completion_salt:
  file.managed:
    - name: /etc/bash_completion.d/salt
    - source: salt://bash/files/completions/salt
