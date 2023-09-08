  {% if "internal_options_conf" in pillar["wazuh"]["wazuh_manager"] %}
{% include "wazuh/includes/internal_options_conf.sls"  with context %}
  {% endif %}

backup_ossec_conf_and_internal_options_conf:
  cmd.run:
    - name: 'rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; rsync -av /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/internal_options.conf /tmp/internal_options.conf'
