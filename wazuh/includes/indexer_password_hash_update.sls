{% set indexer_password_hash_cmd = 'docker run --rm -i ' + pillar["wazuh"]["wazuh_indexer"]["image"] + ' bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p ' + pillar["wazuh"]["wazuh_dashboard"]["env_vars"]["INDEXER_PASSWORD"] + ' | tail -n -1' %}
{% set indexer_password_hash = salt['cmd.run'](indexer_password_hash_cmd) %}

wazuh_indexer_password_hash_update:
  file.replace:
    - name: /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.yml
    - pattern: 'admin:\n\s+hash:.*'
    - repl: 'admin:\n  hash: "{{ indexer_password_hash }}"'
    - backup: '.bak'
