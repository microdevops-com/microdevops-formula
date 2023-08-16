pull_wazuh_manager:
  cmd.run:
    - name: docker pull {{ pillar["wazuh"]["wazuh_manager"]["image"] }}
wazuh_manager_container:
  docker_container.running:
    - name: wazuh.manager
    - hostname: wazuh.manager
    - image: {{ pillar["wazuh"]["wazuh_manager"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_api_configuration:/var/ossec/api/configuration
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc:/var/ossec/etc
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_logs:/var/ossec/logs
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_queue:/var/ossec/queue
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_var_multigroups:/var/ossec/var/multigroups
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_integrations:/var/ossec/integrations
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_active_response:/var/ossec/active-response/bin
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_agentless:/var/ossec/agentless
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_wodles:/var/ossec/wodles
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_stats:/var/ossec/stats
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/filebeat_etc:/etc/filebeat
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/filebeat_var:/var/lib/filebeat
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/root-ca-manager.pem:/etc/ssl/root-ca.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/wazuh.manager.pem:/etc/ssl/filebeat.pem
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/wazuh.manager-key.pem:/etc/ssl/filebeat.key
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf:/wazuh-config-mount/etc/ossec.conf
    - publish:
      - 1514:1514
      - 1515:1515
      - 514:514/udp
      - 55000:55000
    - networks:
      - wazuh
    - environment:
    {%- for var_key, var_val in pillar["wazuh"]["wazuh_manager"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}
