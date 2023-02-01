pkg:
  docker-compose:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose'
            - runas: 'root'
          2:
            - name: 'chmod +x /usr/local/bin/docker-compose'
            - runas: 'root'
