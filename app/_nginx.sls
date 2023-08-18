      {%- if "nginx" in app %}

        {%- set _nginx_sites_available_dir = app["nginx"].get("sites_available_dir", "/etc/nginx/sites-available") %}
        {%- set _nginx_sites_enabled_dir = app["nginx"].get("sites_enabled_dir", "/etc/nginx/sites-enabled") %}

        {%- set _app_nginx_root = app["nginx"]["root"]|replace("__APP_NAME__", app_name) %}
        {%- set _app_nginx_access_log = app["nginx"]["log"]["access_log"]|replace("__APP_NAME__", app_name) %}
        {%- set _app_nginx_error_log = app["nginx"]["log"]["error_log"]|replace("__APP_NAME__", app_name) %}

        {%- if "auth_basic" in app["nginx"] and "auth" in app["nginx"]["auth_basic"] %}
app_{{ app_type }}_nginx_apache_utils_{{ loop_index }}:
  pkg.installed:
    - pkgs:
      - apache2-utils

          {%- for item in app["nginx"]["auth_basic"]["auth"] %}
app_{{ app_type }}_nginx_htaccess_user_{{ loop_index }}_{{ loop.index }}:
  webutil.user_exists:
    - name: '{{ item["user"] }}'
    - password: '{{ item["pass"] }}'
    - htpasswd_file: {{ _app_app_root }}/.htpasswd
    - force: True
    - runas: {{ _app_user }}

          {%- endfor %}

          {%- if "omit_options" in app["nginx"]["auth_basic"] and app["nginx"]["auth_basic"]["omit_options"] %}
            {%- set auth_basic_block = 'set $toggle "Restricted Content"; if ($request_method = OPTIONS) { set $toggle off; } auth_basic $toggle; auth_basic_user_file ' ~ _app_app_root ~ '/.htpasswd;' %}
          {%- else %}
            {%- set auth_basic_block = 'auth_basic "Restricted Content"; auth_basic_user_file ' ~ _app_app_root ~ '/.htpasswd;' %}
          {%- endif %}

        {%- else %}
          {%- set auth_basic_block = ' ' %}
        {%- endif %}

        {%- if "auth_basic" in app["nginx"] and "custom" in app["nginx"]["auth_basic"] %}
          {%- for htaccess_file in app["nginx"]["auth_basic"]["custom"] %}
            {%- set file_loop = loop %}
            {%- for item in htaccess_file["auth"] %}
app_{{ app_type }}_nginx_custom_htaccess_user_{{ loop_index }}_{{ file_loop.index }}_{{ loop.index }}:
  webutil.user_exists:
    - name: '{{ item["user"] }}'
    - password: '{{ item["pass"] }}'
    - htpasswd_file: {{ htaccess_file["path"]|replace("__APP_NAME__", app_name) }}
    - force: True
    - runas: {{ _app_user }}

            {%- endfor %}
          {%- endfor %}
        {%- endif %}

        {%- with %}
          {%- include "app/_nginx/acme.sls" with context %}
        {%- endwith %}

        {%- if "redirects" in app["nginx"] %}
          {%- for redirect in app["nginx"]["redirects"] %}
           {%- with %}
             {%- set loop2_index = loop.index %}
            {%- include "app/_nginx/acme.sls" with context %}
           {%- endwith %}
          {%- endfor %}
        {%- endif %}

        {%- if "dir" in app["nginx"]["log"] %}
app_{{ app_type }}_nginx_log_dir_{{ loop_index }}:
  file.directory:
    - name: {{ app["nginx"]["log"]["dir"]|replace("__APP_NAME__", app_name) }}
    - user: {{ app["nginx"]["log"]["dir_user"]|default(_app_user)|replace("__APP_NAME__", app_name) }}
    - group: {{ app["nginx"]["log"]["dir_group"]|default(_app_group)|replace("__APP_NAME__", app_name) }}
    - mode: {{ app["nginx"]["log"]["dir_mode"]|default("755") }}
    - makedirs: True

app_{{ app_type }}_nginx_logrotate_file_{{ loop_index }}:
  file.managed:
    - name: /etc/logrotate.d/nginx-{{ app_name }}
    - mode: 644
    - contents: |
        {{ _app_nginx_access_log }}
        {{ _app_nginx_error_log }} {
          rotate {{ app["nginx"]["log"]["rotate_count"]|default("31") }}
          {{ app["nginx"]["log"]["rotate_when"]|default("daily") }}
          missingok
          create {{ app["nginx"]["log"]["log_mode"]|default("640") }} {{ app["nginx"]["log"]["log_user"]|default(_app_user)|replace("__APP_NAME__", app_name) }} {{ app["nginx"]["log"]["log_group"]|default(_app_group)|replace("__APP_NAME__", app_name) }}
          compress
          delaycompress
          postrotate
            /usr/sbin/nginx -s reopen
          endscript
        }

        {%- endif %}

        {%- if "link_sites-enabled" in app["nginx"] and app["nginx"]["link_sites-enabled"] %}
app_{{ app_type }}_nginx_link_sites_enabled_{{ loop_index }}:
  file.symlink:
    - name: {{ _nginx_sites_enabled_dir }}/{{ app_name }}.conf
    - target: {{ _nginx_sites_available_dir }}/{{ app_name }}.conf

          {%- if "redirects" in app["nginx"] %}
            {%- for redirect in app["nginx"]["redirects"] %}
app_{{ app_type }}_nginx_link_sites_enabled_redirect_{{ loop_index }}_{{ loop.index }}:
  file.symlink:
    - name: {{ _nginx_sites_enabled_dir }}/{{ app_name }}_redirect_{{ loop.index }}.conf
    - target: {{ _nginx_sites_available_dir }}/{{ app_name }}_redirect_{{ loop.index }}.conf

            {%- endfor %}
          {%- endif %}

        {%- endif %}

        {%- if (pillar["nginx_reload"] is defined and pillar["nginx_reload"]) or ("reload" in app["nginx"] and app["nginx"]["reload"]) %}
app_{{ app_type }}_nginx_reload_{{ loop_index }}:
  cmd.run:
    - name: "/usr/sbin/nginx -t && /usr/sbin/nginx -s reload"

        {%- endif %}

app_{{ app_type }}_nginx_reload_cron_{{ loop_index }}:
  cron.present:
    - identifier: nginx_daily_reload
    - user: root
    - minute: 30
    - hour: 10
    - name: "/usr/sbin/nginx -t -q && /usr/sbin/nginx -s reload"

      {%- endif %}
