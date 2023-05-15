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


{% if pillar["pxc"] is defined and "configs_ini" in pillar["pxc"] %}
{% set separator = salt['pillar.get']('pxc:configs_ini:separator', ' = ') %}

{% macro macro_list(key, val) %}
        {%- if val | is_list %}
        {%- for item in val %}
        {{ key }}{{ separator }}{{ item }}
        {%- endfor %}
        {%- elif val is mapping %}

        {{ key }}
        {%- for item_key, item_val in val.items() %}
        {{- macro_list(item_key, item_val) }}
        {%- endfor %}
        {%- elif val is none and not val %}
        {{ key }}
        {%- else %}
        {{ key }}{{ separator }}{{ val }}
        {%- endif -%}
{% endmacro %}

{% macro macro_config_ini(config_ini_data, separator) %}
        {%- for section, section_data in config_ini_data.items() %}
        {{- macro_list(section, section_data) }}
        {%- endfor -%}
{% endmacro %}


  {%- for config_ini_name, config_ini_data in pillar["pxc"]["configs_ini"].items() if not config_ini_name in ["dirs", "separator"] %}
pxc_configs_ini_{{ loop.index }}:
  file.managed:
    - name: {{ config_ini_name }}
    - contents: |
        {{- macro_config_ini(config_ini_data) -}}

  {%- endfor %}
{% endif %}

