pkg:
  forward_root_email:
    when: PKG_BEFORE_DEPLOY
    states:
      - alias.present:
          1:
            - name: root
            - target: {{ root_email }}
      - cmd.run:
          1:
            - name: /usr/bin/newaliases
            - runas: root
