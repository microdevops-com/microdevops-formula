{% if pillar['haproxy'] is defined and pillar['haproxy'] is not none %}
  
  {% from "acme/macros.jinja" import verify_and_issue %}

  {% set haproxy_version = pillar['haproxy'].get('version', '2.6') %}
  {% set os_family = grains['os_family'] %}
  {% set os = grains['os'] %}
  {% set osrelease = grains['osrelease'] %}

  {% if os_family == 'Ubuntu' %}
    {% if haproxy_version == '3.2' and os == 'Ubuntu' and osrelease.startswith('24.') %}
add_repository_3_2_noble:
  pkgrepo.managed:
    - ppa: vbernat/haproxy-3.2
    {% else %}
add_repository:
  pkgrepo.managed:
    - ppa: {{ pillar['haproxy']["ppa"] | default('vbernat/haproxy-2.6') }}
    {% endif %}
  {% endif %}

  {% if os_family == 'Debian' and haproxy_version == '3.2' and os == 'Debian' and osrelease.startswith('12') %}
haproxy_keyring:
  cmd.run:
    - name: curl https://haproxy.debian.net/haproxy-archive-keyring.gpg --create-dirs --output /etc/apt/keyrings/haproxy-archive-keyring.gpg
    - unless: test -f /etc/apt/keyrings/haproxy-archive-keyring.gpg

haproxy_repo:
  file.managed:
    - name: /etc/apt/sources.list.d/haproxy.list
    - contents: 'deb [signed-by=/etc/apt/keyrings/haproxy-archive-keyring.gpg] https://haproxy.debian.net bookworm-backports-3.2 main'

haproxy_update:
  cmd.run:
    - name: apt-get update

haproxy_install:
  pkg.installed:
    - name: haproxy
    - version: 3.2.*
  {% else %}
haproxy_install:
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - haproxy
  {% endif %}

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

        {{ verify_and_issue(acme_config["name"], "haproxy", acme_config["domains"]) }}

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

    {{ verify_and_issue(acme, "haproxy", pillar["haproxy"]["ssl"]["domain"]) }}

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
