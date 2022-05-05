{% if pillar['keepalived'] is defined and pillar['keepalived'] is not none %}

keepalived_install:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - keepalived

keepalived_config:
  file.managed:
    - name: /etc/keepalived/keepalived.conf
    - user: 0
    - group: 0
    - mode: 644
    - source: 'salt://{{ pillar["keepalived"]["config"]["template"] }}'
    - template: jinja

keepalived_run:
  service.running:
    - name: keepalived
    - enable: True

keepalived_reload:
  cmd.run:
    - name: systemctl reload keepalived
    - onchanges:
        - file: /etc/keepalived/keepalived.conf

{% endif %}
