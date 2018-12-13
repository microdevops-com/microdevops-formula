pkg:
  k8s_lxc_host:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - file.line: 
          1: 
            - name: '/etc/rc.local'
            - mode: ensure
            - before: '^exit\ 0$'
            - content: 'echo "1048576" > /sys/module/nf_conntrack/parameters/hashsize'
      - cmd.run:
          1:
            - name: 'echo "1048576" > /sys/module/nf_conntrack/parameters/hashsize'
