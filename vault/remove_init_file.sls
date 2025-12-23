{% if pillar['vault'] is defined %}

{% set init_file = pillar['vault'].get('init', {}).get('output_file', '/opt/vault/init-temp.json') %}

vault_remove_init_file:
  file.absent:
    - name: {{ init_file }}

{% endif %}
