{% if pillar["vault"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {# Support for both binary installation (with version) and apt installation (legacy) #}
  {% set vault_version = pillar['vault'].get('version', None) %}
  {% set use_binary = vault_version is not none %}

  {% if use_binary %}
  {% set vault_url = "https://releases.hashicorp.com/vault/" ~ vault_version ~ "/vault_" ~ vault_version ~ "_linux_amd64.zip" %}

vault_user:
  user.present:
    - name: vault
    - createhome: False
    - shell: /bin/false
    - system: True

vault_home_dir:
  file.directory:
    - name: /opt/vault
    - user: vault
    - group: vault
    - dir_mode: 755
    - makedirs: True

vault_group:
  group.present:
    - name: vault
    - system: True

vault_install_prerequisites:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - python3-pip
        - unzip
        - curl

vault_extract_to_usrbin:
  cmd.run:
    - name: |
        curl -sL {{ vault_url }} -o /tmp/vault_temp.zip
        unzip -j -o /tmp/vault_temp.zip vault -d /usr/bin
        rm /tmp/vault_temp.zip
    - shell: /bin/bash
    - unless: /usr/bin/vault version 2>/dev/null | grep -q "Vault v{{ vault_version }}"
    - require:
      - pkg: vault_install_prerequisites

vault_set_perms:
  cmd.run:
    - name: chmod 0755 /usr/bin/vault
    - unless: test -x /usr/bin/vault
    - require:
      - cmd: vault_extract_to_usrbin

vault_systemd_unit:
  file.managed:
    - name: /lib/systemd/system/vault.service
    - mode: 644
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description="HashiCorp Vault - A tool for managing secrets"
        Documentation=https://www.vaultproject.io/docs/
        Requires=network-online.target
        After=network-online.target
        ConditionFileNotEmpty=/etc/vault.d/vault.hcl
        StartLimitIntervalSec=60
        StartLimitBurst=3

        [Service]
        Type=notify
        EnvironmentFile=/etc/vault.d/vault.env
        User=vault
        Group=vault
        ProtectSystem=full
        ProtectHome=read-only
        PrivateTmp=yes
        PrivateDevices=yes
        SecureBits=keep-caps
        AmbientCapabilities=CAP_IPC_LOCK
        CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
        NoNewPrivileges=yes
        ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
        ExecReload=/bin/kill --signal HUP $MAINPID
        KillMode=process
        KillSignal=SIGINT
        Restart=on-failure
        RestartSec=5
        TimeoutStopSec=30
        LimitNOFILE=65536
        LimitMEMLOCK=infinity

        [Install]
        WantedBy=multi-user.target

  {% else %}
  {# Legacy installation method via apt #}

vault_keyring_dir:
  file.directory:
    - name: /usr/share/keyrings
    - dir_mode: 755
    - makedirs: True

vault_keyring_download:
  cmd.run:
    - name: wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    - unless: test -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
    - require:
      - file: vault_keyring_dir

vault_repo_file:
  file.managed:
    - name: /etc/apt/sources.list.d/hashicorp.list
    - mode: 644
    - contents: 'deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com {{ grains["oscodename"] }} main'
    - require:
      - cmd: vault_keyring_download

pkgs_install:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - python3-pip
        - wget
        - gnupg
        - vault
    - require:
      - file: vault_repo_file
  {% endif %}

vault_autocomplete_install:
  cmd.run:
    - name: vault -autocomplete-install || true

vault_config_dir:
  file.directory:
    - names:
      - /etc/vault.d
    - dir_mode: 755
    - user: vault
    - group: vault
    - makedirs: True

  {% if pillar['acme'] is defined and pillar["vault"]["acme"] is defined and pillar["vault"]["acme"]["enable"] | default(false) and  pillar["vault"]["acme"]["domain"] is defined %}
  {% set acme_account = pillar['acme'].keys() | first %} 

    {{ verify_and_issue(acme_account, "vault", pillar["vault"]["acme"]["domain"]) }}

cert_permissions:
  cmd.run:
    - name: /usr/bin/chown vault:vault /opt/acme/cert/vault_{{ pillar["vault"]["acme"]["domain"] }}*

cert_permissions_cron:
  cron.present:
    - name: /usr/bin/chown vault:vault /opt/acme/cert/vault_{{ pillar["vault"]["acme"]["domain"] }}*
    - identifier: set permissions for vault certificate
    - user: root
    - minute: 0
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

vault_systemd_override_dir:
  file.directory:
    - name: /usr/lib/systemd/system/vault.service.d
    - dir_mode: 755
    - makedirs: True

vault_enable_capabilities:
  cmd.run:
    - name: setcap cap_ipc_lock,cap_net_bind_service=+ep /usr/bin/vault || true

vault_systemd_capabilities:
  file.managed:
    - name: /usr/lib/systemd/system/vault.service.d/capabilities.conf
    - mode: 644
    - user: root
    - group: root
    - contents: |
        [Service]
        CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK CAP_NET_BIND_SERVICE
        AmbientCapabilities=CAP_IPC_LOCK CAP_NET_BIND_SERVICE

vault_disable_core_dump:
  file.managed:
    - name: /usr/lib/systemd/system/vault.service.d/disable-core-dump.conf
    - mode: 644
    - user: root
    - group: root
    - makedirs: True
    - contents: |
        [Service]
        LimitCORE=0

vault_systemd_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: vault_systemd_capabilities
      - file: vault_disable_core_dump

vault_service_enable_and_start:
  service.running:
    - name: vault
    - enable: true
    - require:
      - cmd: vault_systemd_daemon_reload

vault_service_restart:
  cmd.run:
    - name: sleep 5; systemctl restart vault
    - onchanges:
        - file: /etc/vault.d/vault.hcl
        - file: /etc/vault.d/vault.env
        - file: /usr/lib/systemd/system/vault.service.d/disable-core-dump.conf
        - file: /usr/lib/systemd/system/vault.service.d/capabilities.conf
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
        is_leader="$(curl -sk {{ pillar['vault']['env_vars']['VAULT_ADDR'] }}/v1/sys/leader | jq --raw-output '.is_self')"
        find $snapshots_dir -type f -mtime +{{ pillar["vault"]["snapshots"]["retention"] | default(1) }} -delete
        if ${is_leader}; then
          echo "make raft snapshot $snapshots_dir/vault_$timestamp.snap ..."
          export VAULT_SKIP_VERIFY=true
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

