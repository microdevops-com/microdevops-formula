{% if pillar["openbao"] is defined %}

{% set init_file = pillar["openbao"].get("init", {}).get("output_file", "/root/openbao-init.json") %}

openbao_remove_init_file:
  file.absent:
    - name: {{ init_file }}

{% endif %}
