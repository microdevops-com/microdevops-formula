{% if pillar["logrotate"] is defined %}

  {%- for config in pillar["logrotate"]["configs"] %}
logrotate_config_{{ loop.index }}:
  file.managed:
    - name: {{ config["path"] }}
    - contents: {{ config["contents"] | yaml_encode }}

  {%- endfor %}

{% endif %}
