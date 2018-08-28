# usage
# salt -C 'G@kernel:Linux' state.apply salt.minion_update
salt_minion_update:
  cmd.run:
    - name: |
        exec 0>&- # close stdin
        exec 1>&- # close stdout
        exec 2>&- # close stderr
        nohup /bin/sh -c 'salt-call --local pkg.install salt-minion && salt-call --local service.restart salt-minion' &
