{% if pillar["wazuh"] is defined %}
stopped_containers:
  docker_container.stopped:
    - names:
      - wazuh.dashboard
      - wazuh.manager 

Disable shard allocation:
  cmd.run:
    - name: "curl -sX PUT https://{{ pillar['wazuh']['domain'] }}:9200/_cluster/settings  -u '{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_USERNAME'] }}:{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_PASSWORD'] }}' -k -H 'Content-Type: application/json' -d '{\"persistent\": {\"cluster.routing.allocation.enable\": \"primaries\"}}'"
    
Stop non-essential indexing and perform a synced flush:
  cmd.run:
    - name: curl -sX POST 'https://{{ pillar["wazuh"]["domain"] }}:9200/_flush/synced' -u '{{ pillar["wazuh"]["wazuh_manager"]["env_vars"]["INDEXER_USERNAME"] }}:{{ pillar["wazuh"]["wazuh_manager"]["env_vars"]["INDEXER_PASSWORD"] }}' -k

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

Enable shard allocation:
  cmd.run:
    - name: "sleep 30; curl -sX PUT 'https://{{ pillar['wazuh']['domain'] }}:9200/_cluster/settings' -u '{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_USERNAME'] }}:{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_PASSWORD'] }}' -k -H 'Content-Type: application/json' -d '{\"persistent\": {\"cluster.routing.allocation.enable\": \"all\"}}'"
    - shell: /bin/bash

pull_wazuh_manager:
  cmd.run:
    - name: docker pull {{ pillar["wazuh"]["wazuh_manager"]["image"] }}

backup_ossec_conf:
  cmd.run:
    - name: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'

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
    - require:
      - cmd: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'

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

restore_internal_options_conf:
  cmd.run:
    - name: 'sleep 30; rsync -av /tmp/internal_options.conf /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf; docker restart wazuh.manager'
    - require:
      - cmd: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'
{% endif %}