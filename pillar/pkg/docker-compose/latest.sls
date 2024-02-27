pkg:
  docker-compose:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://github.com/docker/compose/releases/download/`curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "tag_name" | cut -d\" -f4`/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose'
            - runas: 'root'
          2:
            - name: 'chmod +x /usr/local/bin/docker-compose'
            - runas: 'root'
