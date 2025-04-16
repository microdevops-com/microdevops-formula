{% if pillar["bootstrap"] is defined and "sshd_prohibit_password" in pillar["bootstrap"] and pillar["bootstrap"]["sshd_prohibit_password"] %}
bootstrap_sshd_prohibit_password:
  file.keyvalue:
    - name: /etc/ssh/sshd_config
    - key: PermitRootLogin
    - value: prohibit-password
    - separator: " "
    - uncomment: "#"
    - key_ignore_case: True
    - append_if_not_found: True
    - unless: |
        sshd -T | grep -i permitrootlogin | grep -q -e without-password -e prohibit-password

bootstrap_sshd_prohibit_password_service:
  service.running:
    - name: sshd
    - enable: True
    - reload: True
    - watch:
      - file: bootstrap_sshd_prohibit_password

{% endif %}
