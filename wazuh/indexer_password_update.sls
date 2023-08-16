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
{% include "wazuh/includes/restore_internal_options_conf.sls"               with context %}

{% endif %}
