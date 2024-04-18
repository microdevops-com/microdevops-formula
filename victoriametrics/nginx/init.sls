
{% from "acme/macros.jinja" import verify_and_issue %}

{%- set cert_prefix = "vmserver" %}
{%- set template = "vhost.jinja" %}

{{ kind }}_{{ vm_name }}_nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

{{ kind }}_{{ vm_name }}_htpasswd_dir:
  file.directory:
    - name: /etc/nginx/htpasswd

  {%- for auth in vm_data["nginx"].get("auth_basic",[]) %}
{{ kind }}_{{ vm_name }}_basic_auth_{{ auth["username"] }}:
  webutil.user_exists:
    - name: {{ auth["username"] }}
    - password: {{ auth["password"] }}
    - htpasswd_file: /etc/nginx/htpasswd/{{ service_name }}
    - force: true
  {%- endfor %}

  {% for server in vm_data["nginx"]["servers"] if "acme_account" in server.keys() %}

    {{ verify_and_issue(server["acme_account"], cert_prefix, server["names"]) }}

  {%- endfor %}

{{ kind }}_{{ vm_name }}_nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/{{ service_name }}.conf
    - source: salt://victoriametrics/nginx/{{ template }}
    - template: jinja
    - context:
        cert_prefix: {{ cert_prefix }}
        vm_name: {{ vm_name }}
        vm_data: {{ vm_data }}
        service_name: {{ service_name }}

{{ kind }}_{{ vm_name }}_nginx_files_symlink_1:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ service_name }}.conf
    - target: /etc/nginx/sites-available/{{ service_name }}.conf

{{ kind }}_{{ vm_name }}_nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

{{ kind }}_{{ vm_name }}_nginx_reload:
  cmd.run:
    - runas: root
    - name: nginx -t && nginx -s reload
    - watch:
      - file: /etc/nginx/sites-available/{{ service_name }}.conf

{{ kind }}_{{ vm_name }}_nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
