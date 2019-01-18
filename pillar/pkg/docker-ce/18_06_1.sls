pkg:
  docker-ce:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkgrepo.managed:
          1:
            - humanname: Docker CE Repository
            - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable
            - file: /etc/apt/sources.list.d/docker-ce.list
            - key_url: https://download.docker.com/linux/ubuntu/gpg
      - pkg.installed:
          1:
            - refresh: True
            - pkgs:
              - docker-ce: '18.06.1*'
              - python-docker
      - service.running:
          1:
            - name: docker
