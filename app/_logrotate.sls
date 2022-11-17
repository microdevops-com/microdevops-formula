      {%- if "logrotate" in app %}

        {%- set _logrotate_sites_available_dir = app["logrotate"].get("sites_available_dir", "/etc/logrotate/sites-available") %}

        {%- for logrotate_file in app["logrotate"] %}
app_{{ app_type }}_logrotate_custom_config_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: /etc/logrotate.d/app-{{ app_name }}-{{ logrotate_file["name"] }}
    - contents: {{ logrotate_file["contents"] | yaml_encode | replace("__APP_NAME__", app_name) }}

        {%- endfor %}

      {%- endif %}
