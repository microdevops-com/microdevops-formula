{% if "internal_options_conf" in pillar["wazuh"]["wazuh_manager"] %}
  {%- for key, val in pillar["wazuh"]["wazuh_manager"]["internal_options_conf"].items() %}
internal_options_conf_set_{{ key }}:
  file.replace:
    - name: '/opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc/internal_options.conf'
    - pattern: '^ *{{ key }}.*$'
    - repl: '{{ key }}={{ val }}'
  {%- endfor %}
{% endif %}
