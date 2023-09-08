{%- for var_key, var_val in pillar["wazuh"]["wazuh_manager"]["internal_options_conf"].items() %}
internal_options_conf_{{ loop.index }}:
  file.replace:
    - name: '/opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc/internal_options.conf'
    - pattern: '^ *{{ var_key }}.*$'
    - repl: '{{ var_key }} = {{ var_val }};'
{%- endfor %}
