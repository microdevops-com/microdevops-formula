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

{% if pillar["haproxy"]["ssl"] is defined %}
  {% if pillar["acme"] is defined %}
    {% if pillar["haproxy"]["ssl"]["acme_configs"] is defined %}
      {% for acme_config in pillar["haproxy"]["ssl"]["acme_configs"] %}
{% set cert_name = acme_config["domains"][0] %}
haproxy_cert_{{ cert_name }}_gen_1:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_config["name"] }}/verify_and_issue.sh haproxy {%- for domain in acme_config["domains"] %} {{ domain }} {%- endfor -%}"

create_pem_dir:
  file.directory:
    - name: {{ acme_config["pemdir"] }}
    - user: root
    - group: root
    - file_mode: 664
    - dir_mode: 775
    - makedirs: True

haproxy_cert_{{ cert_name }}_gen_2:
  cmd.run:
    - shell: /bin/bash
    - name: "cat /opt/acme/cert/haproxy_{{ cert_name }}_key.key /opt/acme/cert/haproxy_{{ cert_name }}_fullchain.cer > {{ acme_config["pemdir"] }}{{ cert_name }}.pem"

haproxy restart for pem reload cron:
  cron.present:
    - name: "cat /opt/acme/cert/haproxy_{{ cert_name }}_key.key /opt/acme/cert/haproxy_{{ cert_name }}_fullchain.cer > {{ acme_config["pemdir"] }}{{ cert_name }}.pem && systemctl restart haproxy"
    - identifier: haproxy_{{ acme_config["name"] }}.pem_reload
    - user: root
    - minute: {{ range(6, 54) | random }}
    - hour: 6
      {% endfor %}
    {% else %}
{% set acme = pillar["acme"].keys() | first %}
haproxy_cert_gen_1:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh haproxy {{ pillar["haproxy"]["ssl"]["domain"] }}"

      {% if  pillar["haproxy"]["ssl"]["pemdir"] is defined %}
create_pem_dir:
  file.directory:
    - name: {{ pillar["haproxy"]["ssl"]["pemdir"] }}
    - user: root
    - group: root
    - file_mode: 664
    - dir_mode: 775
    - makedirs: True
      {% endif %}

haproxy_cert_gen_2:
  cmd.run:
    - shell: /bin/bash
    - name: "cat {{ pillar["haproxy"]["ssl"]["cert"] }} {{ pillar["haproxy"]["ssl"]["key"] }} > {{ pillar["haproxy"]["ssl"]["pem"] }}"
haproxy restart for pem reload cron:
  cron.present:
    - name: "cat {{ pillar["haproxy"]["ssl"]["cert"] }} {{ pillar["haproxy"]["ssl"]["key"] }} > {{ pillar["haproxy"]["ssl"]["pem"] }} && systemctl restart haproxy"
    - identifier: haproxy_pem_reload
    - user: root
    - minute: 15
    - hour: 6
    {% endif %}
  {% endif %}
{% endif %}

haproxy_run:
  service.running:
    - name: haproxy
    - enable: True

haproxy_restart:
  cmd.run:
    - name: systemctl restart haproxy
    - onchanges:
        - file: /etc/haproxy/haproxy.cfg
{% endif %}
