{% if pillar["logrotate"] is defined %}

  {%- for config in pillar["logrotate"]["configs"] %}
logrotate_config_{{ loop.index }}:
  file.managed:
    - name: {{ config["path"] }}
    - contents: {{ config["contents"] | yaml_encode }}

  {%- endfor %}

  {%- if pillar["logrotate"]["custom_scripts"] is defined %}
  
    {%- for custom_script in pillar["logrotate"]["custom_scripts"] %}
logrotate_custom_script_{{ loop.index }}:
  file.managed:
    - name: {{ custom_script["path"] }}
    - contents: {{ custom_script["contents"] | yaml_encode }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

    {%- endfor %}

  {%- endif %}

{% endif %}
