
{% from "acme/macros.jinja" import verify_and_issue %}

{%- set cert_prefix = "loki-gateway" if loki_data["nginx"].get("gateway", False) else "loki" %}
{%- set template = "vhost-gw.jinja" if loki_data["nginx"].get("gateway", False) else "vhost.jinja" %}
loki_{{ loki_name }}_nginx_install:
  pkg.installed:
    - pkgs:
  {% if loki_data.get("nginx", {"install": False}).get("install", True) %}
      - nginx
  {% endif %}
      - apache2-utils

nginx_mkdir:
  file.directory:
    - name: /etc/nginx
    - user: root
    - group: root
    - mode: 755

  {%- for auth in loki_data["nginx"].get("auth_basic",[]) %}
loki_{{ loki_name }}_basic_auth_{{ auth["username"] }}:
  webutil.user_exists:
    - name: {{ auth["username"] }}
    - password: {{ auth["password"] }}
    - htpasswd_file: {{ "/etc/nginx/htpasswd_" ~ loki_name }}
    - force: true
  {%- endfor %}


  {% for server in loki_data["nginx"]["servers"] if "acme_account" in server.keys() %}

    {{ verify_and_issue(server["acme_account"], cert_prefix, server["names"]) }}

  {%- endfor %}

  {% if loki_data["nginx"].get("separate_config", True) %}
    {%- set config_path = "/etc/nginx/sites-available/" ~ loki_name ~ ".conf" %}
    {%- set config_path = loki_data["nginx"].get("config_path", config_path) %}
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

  {% if loki_data.get("nginx", {"install": False}).get("install", True) %}
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
  {% endif %}
