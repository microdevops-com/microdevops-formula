{%- if pillar["wazuh"]["wazuh_manager"]["postfix"] is defined %}
pull_postfix_image:
  cmd.run:
    - name: docker pull juanluisbaptiste/postfix:1.7.1
wazuh_postfix_container:
  docker_container.running:
    - name: wazuh.postfix
    - hostname: wazuh.postfix
    - image: juanluisbaptiste/postfix:1.7.1
    - detach: True
    - restart_policy: unless-stopped
    - networks:
      - wazuh
    - environment:
      - SMTP_SERVER: {{ pillar["wazuh"]["wazuh_manager"]["postfix"]["SMTP_SERVER"] }}
      - SMTP_USERNAME: {{ pillar["wazuh"]["wazuh_manager"]["postfix"]["SMTP_USERNAME"] }}
      - SMTP_PASSWORD: {{ pillar["wazuh"]["wazuh_manager"]["postfix"]["SMTP_PASSWORD"] }}
      - SERVER_HOSTNAME: {{ grains["id"] }}
      - ALWAYS_ADD_MISSING_HEADERS: "yes"
{%- endif %}

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
      {%- if var_key not in ["INDEXER_USERNAME","IDEXER_URL","FILEBEAT_SSL_VERIFICATION_MODE","SSL_CERTIFICATE_AUTHORITIES","SSL_CERTIFICATE","SSL_KEY"] %}
      - {{ var_key }}: {{ var_val }}
      {%- endif %}
    {%- endfor %}
      - INDEXER_USERNAME: admin
      - IDEXER_URL: https://wazuh.indexer:9200
      - FILEBEAT_SSL_VERIFICATION_MODE: full
      - SSL_CERTIFICATE_AUTHORITIES: /etc/ssl/root-ca.pem
      - SSL_CERTIFICATE: /etc/ssl/filebeat.pem
      - SSL_KEY: /etc/ssl/filebeat.key

{%- if pillar["wazuh"]["wazuh_manager"]["ossec_config"] is defined %}
ossec_config:
  file.managed:
    - name: /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc/ossec.conf
    - source: 
        - {{ pillar["wazuh"]["wazuh_manager"]["ossec_config"]["template"] }}
    - template: jinja
    - user: 101
    - group: 101
    - mode: 660
    - defaults:
        values: {{ pillar["wazuh"]["wazuh_manager"]["ossec_config"]["values"] }}

reload manager on changes in ossec.conf:
  cmd.run:
    - name: docker exec wazuh.manager /var/ossec/bin/wazuh-control reload
    - watch:
      - file: /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc/ossec.conf
{%- endif %}