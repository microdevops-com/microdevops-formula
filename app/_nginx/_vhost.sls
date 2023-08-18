{#
Importing this file requires:
  - _nginx_sites_available_dir (string)
  - _app_nginx_access_log (sting)
  - _app_nginx_error_log (string)

  - app_type (string)
  - app_name (string)
  - _app_app_root (string)
  - _app_nginx_root (string)

  - loop_index (int)
  - loop2_index (int)

  - ssl (dict)
  - app (dict) or redirect (dict)
#}

{%- if redirect is defined %}
app_{{ app_type }}_nginx_vhost_config_redirect_{{ loop_index }}_{{ loop2_index }}_{{ id|default("0") }}:
  file.managed:
    - name: {{ _nginx_sites_available_dir }}/{{ app_name }}_redirect_{{ loop2_index }}.conf
    - source: {{ redirect["vhost_config"]|replace("__APP_NAME__", app_name) }}
    - template: jinja
    - defaults:
        domain: {{ app["nginx"]["domain"] }}
        redir_nginx_sites_available_direct: {{ redirect["domain"] }}
        ssl_cert: {{ ssl.get("cert","") | replace("__APP_NAME__", app_name) }}
        ssl_key: {{ ssl.get("key","") | replace("__APP_NAME__", app_name) }}
        ssl_chain: {{ ssl.get("chain","") | replace("__APP_NAME__", app_name) }}

{%- else %}

app_{{ app_type }}_nginx_vhost_config_{{ loop_index }}_{{ loop2_index }}_{{ id|default("0") }}:
  file.managed:
    - name: {{ _nginx_sites_available_dir }}/{{ app_name }}.conf
        {%- if "vhost_contents" in app["nginx"] %}
    - contents: {{ app["nginx"]["vhost_contents"] | replace("__APP_NAME__", app_name) }}
        {%- else %}
    - source: {{ app["nginx"]["vhost_config"]|replace("__APP_NAME__", app_name) }}
    - template: jinja
    - defaults:
        app_name: {{ app_name }}
        app_root: {{ _app_app_root }}
        domain: {{ app["nginx"]["domain"] }}
        nginx_root: {{ _app_nginx_root }}
        access_log: {{ _app_nginx_access_log }}
        error_log: {{ _app_nginx_error_log }}
        ssl_cert: {{ ssl.get("cert","") | replace("__APP_NAME__", app_name) }}
        ssl_key: {{ ssl.get("key","") | replace("__APP_NAME__", app_name) }}
        ssl_chain: {{ ssl.get("chain","") | replace("__APP_NAME__", app_name) }}
        auth_basic_block: '{{ auth_basic_block }}'
          {%- if "vhost_defaults" in app["nginx"] %}
            {%- for def_key, def_val in app["nginx"]["vhost_defaults"].items() %}
        {{ def_key }}: {{ def_val|replace("__APP_NAME__", app_name)|yaml_encode }}
            {%- endfor %}
          {%- endif %}
        {%- endif %}
{%- endif %}
