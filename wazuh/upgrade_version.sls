{% if pillar["wazuh"] is defined %}

stopped_containers:
  docker_container.stopped:
    - names:
      - wazuh.dashboard
      - wazuh.manager 

Disable shard allocation:
  cmd.run:
    - name: "curl -sX PUT https://{{ pillar['wazuh']['domain'] }}:9200/_cluster/settings  -u 'admin:{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_PASSWORD'] }}' -k -H 'Content-Type: application/json' -d '{\"persistent\": {\"cluster.routing.allocation.enable\": \"primaries\"}}'"
    
Stop non-essential indexing and perform a synced flush:
  cmd.run:
    - name: curl -sX POST 'https://{{ pillar["wazuh"]["domain"] }}:9200/_flush/synced' -u 'admin:{{ pillar["wazuh"]["wazuh_manager"]["env_vars"]["INDEXER_PASSWORD"] }}' -k

{% include "wazuh/includes/indexer.sls"                                     with context %}

Enable shard allocation:
  cmd.run:
    - name: "sleep 30; curl -sX PUT 'https://{{ pillar['wazuh']['domain'] }}:9200/_cluster/settings' -u 'admin:{{ pillar['wazuh']['wazuh_manager']['env_vars']['INDEXER_PASSWORD'] }}' -k -H 'Content-Type: application/json' -d '{\"persistent\": {\"cluster.routing.allocation.enable\": \"all\"}}'"
    - shell: /bin/bash

  {% if "internal_options_conf" in pillar["wazuh"]["wazuh_manager"] %}
{% include "wazuh/includes/internal_options_conf.sls" with context %}
  {% endif %}
{% include "wazuh/includes/backup_ossec_conf_and_internal_options_conf.sls" with context %}
{% include "wazuh/includes/internal_users_yml.sls"                          with context %}
{% include "wazuh/includes/manager.sls"                                     with context %}
{% include "wazuh/includes/dashboard.sls"                                   with context %}
{% include "wazuh/includes/restore_internal_options_conf.sls"               with context %}
{% include "wazuh/includes/applying_changes.sls"                            with context %}
  {% if "internal_options_conf" in pillar["wazuh"]["wazuh_manager"] %}
reload_manager:
  cmd.run:
    - name: docker exec wazuh.manager /var/ossec/bin/wazuh-control reload
  {% endif %}
{% endif %}
