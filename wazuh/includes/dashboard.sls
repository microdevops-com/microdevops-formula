pull_wazuh_dashboard:
  cmd.run:
    - name: docker pull {{ pillar["wazuh"]["wazuh_dashboard"]["image"] }}
wazuh_dashboard_container:
  docker_container.running:
    - name: wazuh.dashboard
    - hostname: wazuh.dashboard
    - image: {{ pillar["wazuh"]["wazuh_dashboard"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/acme/cert/wazuh_{{ pillar["wazuh"]["domain"] }}_fullchain.cer:/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem
      - /opt/acme/cert/wazuh_{{ pillar["wazuh"]["domain"] }}_key.key:/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/root-ca.pem:/usr/share/wazuh-dashboard/certs/root-ca.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_dashboard/opensearch_dashboards.yml:/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_dashboard/wazuh.yml:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
    - publish:
      - 443:5601
    - networks:
      - wazuh
    - environment:
    {%- for var_key, var_val in pillar["wazuh"]["wazuh_dashboard"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}
    - require:
      - docker_container: wazuh.indexer
    - links:
      - wazuh.indexer:wazuh.indexer
      - wazuh.manager:wazuh.manager
