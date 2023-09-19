{% if pillar["wazuh"] is defined %}

stopped_containers:
  docker_container.stopped:
    - names:
      - wazuh.dashboard
      - wazuh.manager 
      - wazuh.indexer

  {% if "internal_options_conf" in pillar["wazuh"]["wazuh_manager"] %}
{% include "wazuh/includes/internal_options_conf.sls" with context %}
  {% endif %}
{% include "wazuh/includes/backup_ossec_conf_and_internal_options_conf.sls" with context %}
{% include "wazuh/includes/internal_users_yml.sls"                          with context %}
{% include "wazuh/includes/indexer.sls"                                     with context %}
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
