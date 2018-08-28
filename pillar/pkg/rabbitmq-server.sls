pkg:
  rabbitmq-server:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkgrepo.managed:
          1:
            - humanname: RabbitMQ Repository
            - name: deb http://www.rabbitmq.com/debian/ testing main
            - file: /etc/apt/sources.list.d/rabbitmq.list
            - key_url: https://www.rabbitmq.com/rabbitmq-release-signing-key.asc
      - pkg.latest:
          1:
            - pkgs:
              - rabbitmq-server
      - file.directory:
          '/etc/systemd/system/rabbitmq-server.service.d':
            - makedirs: True
      - file.managed:
          '/etc/default/rabbitmq-server':
            - contents: |
                ulimit -n 65536
          '/etc/systemd/system/rabbitmq-server.service.d/limits.conf':
            - contents: |
                [Service]
                LimitNOFILE=65536
      - cmd.run:
          1:
            - name: 'systemctl daemon-reload'
            - runas: 'root'
          2:
            - name: 'service rabbitmq-server restart'
            - runas: 'root'
