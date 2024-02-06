
{%- set cert_prefix = "loki-gateway" if loki_data["nginx"].get("gateway", False) else "loki" %}
{%- set template = "vhost-gw.jinja" if loki_data["nginx"].get("gateway", False) else "vhost.jinja" %}

loki_{{ loki_name }}_nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils


  {%- for auth in loki_data["nginx"].get("auth_basic",[]) %}
loki_{{ loki_name }}_basic_auth_{{ auth["username"] }}:
  webutil.user_exists:
    - name: {{ auth["username"] }}
    - password: {{ auth["password"] }}
    - htpasswd_file: {{ "/etc/nginx/htpasswd_" ~ loki_name }}
    - force: true
  {%- endfor %}


  {% for server in loki_data["nginx"]["servers"] if "acme_account" in server.keys() %}
loki_{{ loki_name }}_acme_cert_{{ server["names"][0] }}_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ server["acme_account"] }}/verify_and_issue.sh {{ cert_prefix }} {{ " ".join(server["names"]) }}"
  {%- endfor %}

  {% if loki_data["nginx"].get("separate_config", True) %}
    {%- set config_path = "/etc/nginx/sites-available/" ~ loki_name ~ ".conf" %}
  {%- else %}
    {%- set config_path = "/etc/nginx/nginx.conf" %}
  {%- endif %}

loki_{{ loki_name }}_nginx_files_1:
  file.managed:
    - name: {{ config_path }}
    - source: salt://loki/nginx/{{ template }}
    - template: jinja
    - context:
        nginx_separate_config: {{ loki_data["nginx"].get("separate_config", True) }}
        cert_prefix: {{ cert_prefix }}
        loki_name: {{ loki_name }}
        loki_data: {{ loki_data }}

loki_{{ loki_name }}_nginx_files_symlink_1:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ loki_name }}.conf
    - target: /etc/nginx/sites-available/{{ loki_name }}.conf
    - onlyif:
      - test -f /etc/nginx/sites-available/{{ loki_name }}.conf

loki_{{ loki_name }}_nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

loki_{{ loki_name }}_nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload

loki_{{ loki_name }}_nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
