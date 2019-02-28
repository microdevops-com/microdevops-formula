pkg:
  mongodb:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkgrepo.managed:
          1:
            - humanname: MongoDB Community Edition
            - name: deb [arch=amd64] https://repo.mongodb.org/apt/ubuntu {{ grains['oscodename'] }}/mongodb-org/3.6 multiverse
            - file: /etc/apt/sources.list.d/mongodb-org-3.6.list
            - key_url: https://www.mongodb.org/static/pgp/server-3.6.asc
      - pkg.installed:
          1:
            - refresh: True
            - pkgs:
              - mongodb-org
      - service.running:
          1:
            - name: mongod
