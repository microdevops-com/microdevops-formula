{% if pillar['haproxy'] is defined and pillar['haproxy'] is not none %}

haproxy_install:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - haproxy

haproxy_config:
  file.managed:
    - name: /etc/haproxy/haproxy.cfg
    - user: 0
    - group: 0
    - mode: 644
    - contents: {{ pillar['haproxy']['config'] | yaml_encode }}

haproxy_run:
  service.running:
    - name: haproxy
    - enable: True

haproxy_reload:
  cmd.run:
    - name: systemctl reload haproxy
    - onchanges:
        - file: /etc/haproxy/haproxy.cfg

{% endif %}
