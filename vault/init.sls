{% if pillar["vault"] is defined %}
vault_install_1:
  pkgrepo.managed:
    - humanname: HashiCorp Vault Repository
    - name: deb [arch=amd64] https://apt.releases.hashicorp.com {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/vault.list
    - key_url: https://apt.releases.hashicorp.com/gpg

pkgs_install:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - python3-pip
        - vault

vault_autocomplete_install:
  cmd.run:
    - name: vault -autocomplete-install || true

  {% if pillar['acme'] is defined and pillar["vault"]["acme"] is defined and pillar["vault"]["acme"]["enable"] | default(false) and  pillar["vault"]["acme"]["domain"] is defined %}
  {% set acme_account = pillar['acme'].keys() | first %} 
vault_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_account }}/verify_and_issue.sh vault {{ pillar["vault"]["acme"]["domain"] }} || true"

cert_permissions:
  cmd.run:
    - name: /usr/bin/chown -R vault:vault  /opt/acme/cert/{{ pillar["vault"]["acme"]["domain"] }}/*

cert_permissions_cron:
  cron.present:
    - name: /usr/bin/chown vault:vault -R /opt/acme/cert/{{ pillar["vault"]["acme"]["domain"] }}/*
    - identifier: set permissions for vault certificate
    - user: root
    - minute: 0
    - hour: 1
  {% endif %}
vault_data_dir:
  file.directory:
    - names:
      - /opt/vault/data
      - /opt/vault/snapshots
    - dir_mode: 755
    - file_mode: 600
    - user: vault
    - group: vault
    - recurse:
      - user
      - group
      - mode
    - makedirs: True

vault_config:
  file.managed:
    - name: /etc/vault.d/vault.hcl
    - mode: 644
    - user: vault
    - group: vault
    - contents: |
        {{ pillar["vault"]["config"] | indent(8) }}

vault_env_file:
  file.managed:
    - name: /etc/vault.d/vault.env
    - mode: 644
    - user: vault
    - group: vault
    - contents: |
    {%- for var_key, var_val in pillar["vault"]["env_vars"].items() %}
        {{ var_key }}={{ var_val }}
    {%- endfor %}

vault_set_environment:
  file.replace:
    - name: '/etc/environment'
    - pattern: '^ *VAULT_ADDR=.*$'
    - repl: 'VAULT_ADDR={{ pillar["vault"]["env_vars"]["VAULT_ADDR"] }}'
    - append_if_not_found: True

disable_core_dump:
  file.managed:
    - name: /lib/systemd/system/vault.service.d/disable-core-dump.conf
    - mode: 644
    - user: root
    - group: root
    - makedirs: True
    - contents: |
        [Service]
        LimitCORE=0

systemctl daemon-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - shell: /bin/bash

vault_service_enable_and_start:
  service.running:
    - name: vault
    - enable: true

vault_service_restart:
  cmd.run:
    - name: sleep 5; systemctl restart vault
    - onchanges:
        - file: /etc/vault.d/vault.hcl
        - file: /etc/vault.d/vault.env
        - file: /lib/systemd/system/vault.service.d/disable-core-dump.conf
  {% if pillar["vault"]["snapshots"] is defined %}
  {% set snapshots_dir = pillar["vault"]["snapshots"]["dir"] | default("/opt/vault/snapshots") %}
  {% set cron_minute = pillar["vault"]["snapshots"]["cron_minute"] | default(range(6, 54) | random) %}
  {% set cron_hour = pillar["vault"]["snapshots"]["cron_hour"] | default("*/4") %}
  {% set cron_daymonth = pillar["vault"]["snapshots"]["cron_daymonth"] | default("*") %}
  {% set cron_month = pillar["vault"]["snapshots"]["cron_month"] | default("*") %}
  {% set cron_dayweek = pillar["vault"]["snapshots"]["cron_dayweek"] | default("*") %}

vault_create_snapshots_directory:
  file.directory:
    - name: {{ snapshots_dir }}
    - dir_mode: 755
    - file_mode: 600
    - user: vault
    - group: vault
    - recurse:
      - user
      - group
      - mode
    - makedirs: True


    {% if pillar["vault"]["snapshots"]["enable_raft"] %}
vault_snapshot_raft_script:
  file.managed:
    - name: /opt/vault/snapshot-raft.sh
    - mode: 755
    - contents: |
        #!/bin/bash 
        # snapshot if leader
        timestamp=$(date +'%y-%m-%d_%H-%M-%S')
        snapshots_dir={{ snapshots_dir }}
        is_leader="$(curl -s {{ pillar['vault']['env_vars']['VAULT_ADDR'] }}/v1/sys/leader | jq --raw-output '.is_self')"
        find $snapshots_dir -type f -mtime +{{ pillar["vault"]["snapshots"]["retention"] | default(1) }} -delete
        if ${is_leader}; then
          echo "make raft snapshot $snapshots_dir/vault_$timestamp.snap ..."
          vault operator raft snapshot save ${snapshots_dir}/vault_${timestamp}.snap
        else
          echo "not leader, skipping raft snapshot."
        fi

vault_snapshot_cron:
  cron.present:
    - name: /opt/vault/snapshot-raft.sh
    - identifier: vault_raft_snapshot
    - minute: '{{ cron_minute }}'
    - hour: '{{ cron_hour }}'
    - daymonth: '{{ cron_daymonth }}'
    - month: '{{ cron_month }}'
    - dayweek: '{{ cron_dayweek }}'
    - user: root
    {% endif %}


  {% endif %}
{% endif %}
