{% if pillar["wazuh"] is defined %}

stopped_containers:
  docker_container.stopped:
    - names:
      - wazuh.dashboard
      - wazuh.manager 
      - wazuh.indexer

{% include "wazuh/includes/backup_ossec_conf_and_internal_options_conf.sls" with context %}
{% include "wazuh/includes/indexer_password_hash_update.sls"                with context %}
{% include "wazuh/includes/indexer.sls"                                     with context %}
{% include "wazuh/includes/manager.sls"                                     with context %}
{% include "wazuh/includes/dashboard.sls"                                   with context %}
{% include "wazuh/includes/applying_changes.sls"                            with context %}

restore_internal_options_conf:
  cmd.run:
    - name: 'sleep 30; rsync -av /tmp/internal_options.conf /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf; docker restart wazuh.manager'
    - require:
      - cmd: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'

{% endif %}
