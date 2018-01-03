pkg:
  certbot:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - git.latest:
          certbot:
            - name: https://github.com/certbot/certbot
            - target: /opt/certbot
            - force_reset: True
            - force_fetch: True
