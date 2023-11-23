{% if pillar['keepalived'] is defined and pillar['keepalived'] is not none %}

keepalived_install:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - keepalived

{% if pillar['keepalived']['config']['raw'] is defined %}
keepalived_config:
  file.managed:
    - name: /etc/keepalived/keepalived.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: {{ pillar['keepalived']['config']['raw'] | yaml_encode }}
{% else %}
keepalived_config:
  file.managed:
    - name: /etc/keepalived/keepalived.conf
    - user: 0
    - group: 0
    - mode: 644
    - source: 'salt://{{ pillar["keepalived"]["config"]["template"] }}'
    - template: jinja
{% endif %}

{% if pillar['keepalived']['vrrp_script'] is defined %}
vrrp_script:
  file.managed:
    - name: {{ pillar['keepalived']['vrrp_script']['path'] }}
    - user: 0
    - group: 0
    - mode: 700
    - contents: {{ pillar['keepalived']['vrrp_script']['contents'] | yaml_encode }}
{% endif %}
{% if pillar['keepalived']['notify_master'] is defined %}
notify_master:
  file.managed:
    - name: {{ pillar['keepalived']['notify_master']['path'] }}
    - user: 0
    - group: 0
    - mode: 700
    - contents: {{ pillar['keepalived']['notify_master']['contents'] | yaml_encode }}
{% endif %}
{% if pillar['keepalived']['notify_backup'] is defined %}
notify_master:
  file.managed:
    - name: {{ pillar['keepalived']['notify_backup']['path'] }}
    - user: 0
    - group: 0
    - mode: 700
    - contents: {{ pillar['keepalived']['notify_backup']['contents'] | yaml_encode }}
{% endif %}
{% if pillar['keepalived']['notify_fault'] is defined %}
notify_master:
  file.managed:
    - name: {{ pillar['keepalived']['notify_fault']['path'] }}
    - user: 0
    - group: 0
    - mode: 700
    - contents: {{ pillar['keepalived']['notify_fault']['contents'] | yaml_encode }}
{% endif %}

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
