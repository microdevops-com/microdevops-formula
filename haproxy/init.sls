{% if pillar['haproxy'] is defined and pillar['haproxy'] is not none %}
add_repository:
  pkgrepo.managed:
    - ppa: {{ pillar['haproxy']["ppa"] | default('vbernat/haproxy-2.6') }}

haproxy_install:
  pkg.latest:
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

{% if pillar['haproxy']["ssl"] is defined %}
  {% if pillar['acme'] is defined %}
{% set acme = pillar['acme'].keys() | first %}
haproxy_cert_gen_1:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh haproxy {{ pillar["haproxy"]["ssl"]["domain"] }}"
haproxy_cert_gen_2:
  cmd.run:
    - shell: /bin/bash
    - name: "cat {{ pillar["haproxy"]["ssl"]["cert"] }} {{ pillar["haproxy"]["ssl"]["key"] }} > {{ pillar["haproxy"]["ssl"]["pem"] }}"
  {% endif %}
{% endif %}

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
