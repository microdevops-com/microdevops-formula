{% if pillar["pxc"] is defined and "configs" in pillar["pxc"] %}

  {%- for dir in pillar["pxc"]["configs"]["dirs"] %}
pxc_config_dir_{{ loop.index }}:
  file.directory:
    - name: {{ dir }}
    - makedirs: True

  {%- endfor %}

pxc_my_cnf:
  file.managed:
    - name: /etc/mysql/my.cnf
    - follow_symlinks: False
    - contents:
  {%- for dir in pillar["pxc"]["configs"]["dirs"] %}
        - '!includedir {{ dir }}'
  {%- endfor %}

  {%- for config_name, config_data in pillar["pxc"]["configs"].items() if config_name != "dirs" %}
pxc_config_{{ loop.index }}:
  file.managed:
    - name: {{ config_name }}
    - contents: {{ config_data | yaml_encode }}

  {%- endfor %}

{% endif %}
