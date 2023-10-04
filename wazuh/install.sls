{% if pillar["wazuh"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

vm.max_map_count:
  sysctl.present:
    - value: 262144

acme_cert_verify_and_issue:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh wazuh {{ pillar["wazuh"]["domain"] }}"

cert_permission_fix:
  file.managed:
    - name: /opt/acme/cert/wazuh_{{ pillar["wazuh"]["domain"] }}_fullchain.cer
    - user: 1000
    - group: 1000

key_permission_fix:
  file.managed:
    - name: /opt/acme/cert/wazuh_{{ pillar["wazuh"]["domain"] }}_key.key
    - user: 1000
    - group: 1000
  cmd.run:
    - name: git config --global --add safe.directory /opt/wazuh/{{ pillar["wazuh"]["domain"] }}

cron_cert_key_permissions_fix:
  cron.present:
    - name: /bin/bash -c "chown 1000:1000 /opt/acme/cert/wazuh_{{ pillar['wazuh']['domain'] }}*"
    - identifier: Set permissions on wazuh cert and key
    - user: root
    - user: root
    - minute: 0

wazuh_clone_from_git:
  git.cloned:
    - name: https://github.com/wazuh/wazuh-docker
    - target: /opt/wazuh/{{ pillar["wazuh"]["domain"] }}
    - branch: "v{{ pillar["wazuh"]["release"] }}"

wazuh_certs_generation:
  cmd.run:
    - name: '[ ! -f /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer_ssl_certs/root-ca.key ] && docker-compose -f generate-indexer-certs.yml run --rm generator || true'
    - shell: /bin/bash
    - cwd: /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node

wazuh_data_dirs_1:
  file.directory:
    - names:
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/filebeat_etc
    - makedirs: True
wazuh_data_dirs_2:
  file.directory:
    - names:
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_api_configuration
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_queue
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_integrations
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_wodles      
    - group: 101
wazuh_data_dirs_3:
  file.directory:
    - names:
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_logs
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_stats
    - user: 101
    - group: 101
wazuh_data_dirs_4:
  file.directory:
    - names:
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh-indexer-data
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_var_multigroups
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_active_response
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_agentless
      - /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/filebeat_var
    - user: 1000
    - group: 1000

docker_network:
  docker_network.present:
    - name: wazuh

{% include "wazuh/includes/internal_users_yml.sls"    with context %}
{% include "wazuh/includes/indexer.sls"               with context %}
{% include "wazuh/includes/manager.sls"               with context %}
{% include "wazuh/includes/dashboard.sls"             with context %}
{% include "wazuh/includes/applying_changes.sls"      with context %}
{% include "wazuh/includes/internal_options_conf.sls" with context %}

reload manager on changes in internal_options.conf:
  cmd.run:
    - name: docker exec wazuh.manager /var/ossec/bin/wazuh-control reload
    - watch:
      - file: /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/volumes/wazuh_etc/internal_options.conf

cron_backup_ossec_conf:
  cron.present:
    - name: 'rsync -qa /opt/wazuh/{{ pillar['wazuh']['domain'] }}/volumes/wazuh_etc/ossec.conf /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chown 1000:1000 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf; chmod 644 /opt/wazuh/{{ pillar['wazuh']['domain'] }}/single-node/config/wazuh_cluster/wazuh_manager.conf'
    - identifier: backup_ossec_conf
    - user: root
    - minute: '*/5'

cron_wazuh_dashboard_restart_for_reload_acme_certificates:
  cron.present:
    - name: 'docker restart wazuh.dashboard'
    - identifier: cron_wazuh_dashboard_restart_for_reload_acme_certificates
    - user: root
    - minute: 0
    - hour: 1
{% endif %}
