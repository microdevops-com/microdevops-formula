pkg:
  redis-server:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkg.installed:
          1:
            - pkgs:
                - redis-server
                - redis-tools
      - file.directory:
          '/etc/systemd/system/redis-server.service.d':
            - makedirs: True
      - file.managed:
          '/etc/default/redis-server':
            - contents: |
                ULIMIT=65536
          '/etc/systemd/system/redis-server.service.d/limits.conf':
            - contents: |
                [Service]
                LimitNOFILE=65536
      - cmd.run:
          1:
            - name: 'systemctl daemon-reload'
            - runas: 'root'
          2:
            - name: 'service redis-server restart'
            - runas: 'root'
