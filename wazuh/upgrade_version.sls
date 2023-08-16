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

{% include "wazuh/includes/indexer.sls"    with context %}

Enable shard allocation:
  cmd.run:
    - name: "sleep 30; curl -sX PUT 'https://{{ pillar['wazuh']['domain'] }}:9200/_cluster/settings' -u '{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_USERNAME'] }}:{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_PASSWORD'] }}' -k -H 'Content-Type: application/json' -d '{\"persistent\": {\"cluster.routing.allocation.enable\": \"all\"}}'"
    - shell: /bin/bash

backup_ossec_conf_and_internal_options.conf:
  cmd.run:
    - name: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'

{% include "wazuh/includes/manager.sls"    with context %}
{% include "wazuh/includes/dashboard.sls"  with context %}

restore_internal_options_conf:
  cmd.run:
    - name: 'sleep 30; rsync -av /tmp/internal_options.conf /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf; docker restart wazuh.manager'
    - require:
      - cmd: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'
{% endif %}
