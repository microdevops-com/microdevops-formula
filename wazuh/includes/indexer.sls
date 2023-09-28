pull_wazuh_indexer:
  cmd.run:
    - name: docker pull {{ pillar["wazuh"]["wazuh_indexer"]["image"] }}
wazuh_indexer_container:
  docker_container.running:
    - name: wazuh.indexer
    - hostname: wazuh.indexer
    - image: {{ pillar["wazuh"]["wazuh_indexer"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh-indexer-data:/var/lib/wazuh-indexer
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/root-ca.pem:/usr/share/wazuh-indexer/certs/root-ca.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/wazuh.indexer-key.pem:/usr/share/wazuh-indexer/certs/wazuh.indexer.key
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/wazuh.indexer.pem:/usr/share/wazuh-indexer/certs/wazuh.indexer.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/admin.pem:/usr/share/wazuh-indexer/certs/admin.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/admin-key.pem:/usr/share/wazuh-indexer/certs/admin-key.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/wazuh.indexer.yml:/usr/share/wazuh-indexer/opensearch.yml
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.yml:/usr/share/wazuh-indexer/opensearch-security/internal_users.yml
    - publish:
      - 9200:9200
    - networks:
      - wazuh
    - environment:
    {%- for var_key, var_val in pillar["wazuh"]["wazuh_indexer"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}
    - ulimits:
      - memlock=-1:-1
      - nofile=65536:65536
