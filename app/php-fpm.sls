{% if pillar["app"] is defined and "php-fpm" in pillar["app"] %}

  {%- if "versions" in pillar["app"]["php-fpm"] %}
    {%- set php_fpm = pillar["app"]["php-fpm"] %}
    {%- include "php-fpm/init.sls" with context %}
  {%- endif %}

  {%- for app_name, app in pillar["app"]["php-fpm"]["apps"].items() %}
    {%- if not "deploy_only" in pillar["app"]["php-fpm"] or app_name in pillar["app"]["php-fpm"]["deploy_only"] %}

      {%- set app_type = "php-fpm" %}
      {%- set loop_index = loop.index %}
      {%- set _app_user = app["user"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_group = app["group"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_app_root = app["app_root"]|replace("__APP_NAME__", app_name) %}

      {%- include "app/_user_and_source.sls" with context %}

      {%- set default_pool_log_file = "/var/log/php/" ~ app["pool"]["php_version"] ~ "-fpm/" ~ app_name ~ ".error.log" %}
      {%- if "log" in app["pool"] %}
        {%- set _pool_log_file = app["pool"]["log"]["file"]|replace("__APP_NAME__", app_name)|default(default_pool_log_file) %}
        {%- set _pool_log_dir_user = app["pool"]["log"]["dir_user"]|default(_app_user) %}
        {%- set _pool_log_dir_group = app["pool"]["log"]["dir_group"]|default(_app_group) %}
        {%- set _pool_log_dir_mode = app["pool"]["log"]["dir_mode"]|default("755") %}
        {%- set _pool_log_log_user = app["pool"]["log"]["log_user"]|default(_app_user) %}
        {%- set _pool_log_log_group = app["pool"]["log"]["log_group"]|default(_app_group) %}
        {%- set _pool_log_log_mode = app["pool"]["log"]["log_mode"]|default("644") %}
        {%- set _pool_log_rotate_count = app["pool"]["log"]["rotate_count"]|default("31") %}
        {%- set _pool_log_rotate_when = app["pool"]["log"]["rotate_when"]|default("daily") %}
      {%- else %}
        {%- set _pool_log_file = default_pool_log_file %}
        {%- set _pool_log_dir_user = _app_user %}
        {%- set _pool_log_dir_group = _app_group %}
        {%- set _pool_log_dir_mode = "755" %}
        {%- set _pool_log_log_user = _app_user %}
        {%- set _pool_log_log_group = _app_group %}
        {%- set _pool_log_log_mode = "644" %}
        {%- set _pool_log_rotate_count = "31" %}
        {%- set _pool_log_rotate_when = "daily" %}
      {%- endif %}

app_php-fpm_app_pool_config_{{ loop.index }}:
  file.managed:
    - name: /etc/php/{{ app["pool"]["php_version"] }}/fpm/pool.d/{{ app_name }}.conf
      {%- if "pool_contents" in app["pool"] %}
    - contents: {{ app["pool"]["pool_contents"] | replace("__APP_NAME__", app_name) | yaml_encode }}
      {%- else %}
    - source: {{ app["pool"]["pool_template"] }}
    - template: jinja
    - defaults:
        app_name: {{ app_name }}
        user: {{ _app_user }}
        group: {{ _app_group }}
        php_version: {{ app["pool"]["php_version"] }}
        error_log: {{ _pool_log_file }}
        config: {{ app["pool"]["config"] | yaml_encode }}
      {%- endif %}

app_php-fpm_app_log_dir_{{ loop.index }}:
  file.directory:
    {%- set _pool_log_dir = _pool_log_file | regex_replace('/[^/]*$', '') %}
    - name: {{ _pool_log_dir }}
    - user: {{ _pool_log_dir_user }}
    - group: {{ _pool_log_dir_group }}
    - mode: {{ _pool_log_dir_mode }}
    - makedirs: True

app_php-fpm_app_log_file_{{ loop.index }}:
  file.managed:
    - name: {{ _pool_log_file }}
    - user: {{ _pool_log_log_user }}
    - group: {{ _pool_log_log_group }}
    - mode: {{ _pool_log_log_mode }}
    - dir_mode: {{ _pool_log_dir_mode }}

app_php-fpm_app_logrotate_file_{{ loop.index }}:
  file.managed:
    - name: /etc/logrotate.d/php{{ app["pool"]["php_version"] }}-fpm-{{ app_name }}
    - contents: |
        {{ _pool_log_file }} {
          rotate {{ _pool_log_rotate_count }}
          {{ _pool_log_rotate_when }}
          missingok
          create {{ _pool_log_log_mode }} {{ _pool_log_log_user }} {{ _pool_log_log_group }}
          compress
          delaycompress
          postrotate
            /usr/lib/php/php{{ app["pool"]["php_version"] }}-fpm-reopenlogs
          endscript
        }
        
      {%- if (pillar["php-fpm_reload"] is defined and pillar["php-fpm_reload"]) or ("reload" in app["pool"] and app["pool"]["reload"]) %}
app_php-fpm_app_pool_reload_{{ loop.index }}:
  cmd.run:
    - name: "systemctl reload php{{ app["pool"]["php_version"] }}-fpm"

      {%- endif %}

      {%- include "app/_setup_scripts.sls" with context %}

      {%- include "app/_nginx.sls" with context %}

    {%- endif %}
  {%- endfor %}
{% endif %}
