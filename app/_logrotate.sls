      {%- if "logrotate" in app %}

        {%- for logrotate_file in app["logrotate"] %}
app_{{ app_type }}_logrotate_custom_config_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: /etc/logrotate.d/app-{{ app_name }}-{{ logrotate_file["name"] }}
    - contents: {{ logrotate_file["contents"] | yaml_encode | replace("__APP_NAME__", app_name) }}

        {%- endfor %}

      {%- endif %}
