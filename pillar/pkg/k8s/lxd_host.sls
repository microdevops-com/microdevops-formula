pkg:
  k8s-lxd_host:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - file.managed:
          1: 
            - name: '/etc/rc.local'
            - user: root
            - group: root
            - mode: 0755
            - contents: |
                #!/bin/sh -e
                echo "1048576" > /sys/module/nf_conntrack/parameters/hashsize
                exit 0
      - cmd.run:
          1:
            - name: 'echo "1048576" > /sys/module/nf_conntrack/parameters/hashsize'
