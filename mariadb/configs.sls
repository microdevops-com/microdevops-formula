{% if pillar["mariadb"] is defined and "configs" in pillar["mariadb"] %}

  {%- for config_name, config_data in pillar["mariadb"]["configs"].items() if config_name != "restart_service_on_changes" %}
mariadb_config_{{ loop.index }}:
  file.managed:
    - name: {{ config_name }}
    - contents: {{ config_data | yaml_encode }}
  {%- endfor %}

  {%- if pillar["mariadb"]["configs"]["restart_service_on_changes"] is defined and pillar["mariadb"]["configs"]["restart_service_on_changes"] %}
mariadb_service_restart:
  cmd.run:
    - name: systemctl restart mariadb
    - onchanges:
      - file: mariadb_config_*
  {%- endif %}

{% endif %}
