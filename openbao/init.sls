{% if pillar["openbao"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {% set openbao_version = pillar["openbao"].get("version", "2.6.1") %}
  {% set openbao_url = pillar["openbao"].get("package_url", "https://github.com/openbao/openbao/releases/download/v" ~ openbao_version ~ "/openbao_" ~ openbao_version ~ "_linux_amd64.deb") %}
  {% set config_dir = pillar["openbao"].get("config_dir", "/etc/openbao") %}
  {% set data_dir = pillar["openbao"].get("data_dir", "/opt/openbao/data") %}
  {% set tls_dir = pillar["openbao"].get("tls", {}).get("dir", "/opt/openbao/tls") %}
  {% set seal_dir = pillar["openbao"].get("seal", {}).get("dir", config_dir ~ "/seal") %}
  {% set postgres_cfg = pillar["openbao"].get("postgresql", {}) %}
  {% set install_postgresql = postgres_cfg.get("install", False) %}
  {% set setup_postgresql = postgres_cfg.get("setup", False) %}
  {% set postgresql_user = postgres_cfg.get("user", "openbao") %}
  {% set postgresql_database = postgres_cfg.get("database", "openbao") %}
  {% set postgresql_password = postgres_cfg.get("password") %}
  {% set postgresql_password_file = postgres_cfg.get("password_file", config_dir ~ "/postgres-password") %}

openbao_install_prerequisites:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - ca-certificates
        - curl
        - jq
        - openssl
        - libcap2-bin
{% if install_postgresql %}
        - postgresql
{% endif %}

{% if install_postgresql %}
openbao_postgresql_service:
  service.running:
    - name: postgresql
    - enable: true
    - require:
      - pkg: openbao_install_prerequisites
{% endif %}

openbao_package_download:
  cmd.run:
    - name: curl --fail --location --show-error --output /tmp/openbao_{{ openbao_version }}_linux_amd64.deb {{ openbao_url }}
    - unless: test -f /tmp/openbao_{{ openbao_version }}_linux_amd64.deb
    - require:
      - pkg: openbao_install_prerequisites

openbao_package_install:
  cmd.run:
    - name: apt-get install -y /tmp/openbao_{{ openbao_version }}_linux_amd64.deb
    - unless: bao version 2>/dev/null | grep -q "OpenBao v{{ openbao_version }}"
    - require:
      - cmd: openbao_package_download

openbao_group:
  group.present:
    - name: openbao
    - system: True
    - require:
      - cmd: openbao_package_install

openbao_user:
  user.present:
    - name: openbao
    - createhome: False
    - shell: /bin/false
    - system: True
    - gid: openbao
    - require:
      - group: openbao_group

openbao_config_dir:
  file.directory:
    - name: {{ config_dir }}
    - user: openbao
    - group: openbao
    - dir_mode: 750
    - makedirs: True
    - require:
      - user: openbao_user

openbao_home_dirs:
  file.directory:
    - names:
      - /opt/openbao
      - {{ data_dir }}
      - /opt/openbao/snapshots
    - user: openbao
    - group: openbao
    - dir_mode: 750
    - makedirs: True
    - require:
      - user: openbao_user

{% if setup_postgresql %}
{% if postgresql_password is none %}
openbao_postgresql_password_missing:
  cmd.run:
    - name: |
        echo "ERROR: openbao.postgresql.setup requires openbao.postgresql.password"
        exit 1
{% else %}
openbao_postgresql_password:
  file.managed:
    - name: {{ postgresql_password_file }}
    - mode: 600
    - user: openbao
    - group: openbao
    - contents: |
        {{ postgresql_password }}
    - require:
      - file: openbao_config_dir

openbao_postgresql_user:
  cmd.run:
    - name: |
        su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='{{ postgresql_user }}'\"" | grep -q 1 \
          && su - postgres -c "psql -c \"ALTER USER {{ postgresql_user }} WITH PASSWORD '{{ postgresql_password }}';\"" \
          || su - postgres -c "psql -c \"CREATE USER {{ postgresql_user }} WITH PASSWORD '{{ postgresql_password }}';\""
    - shell: /bin/bash
    - require:
{% if install_postgresql %}
      - service: openbao_postgresql_service
{% else %}
      - pkg: openbao_install_prerequisites
{% endif %}

openbao_postgresql_database:
  cmd.run:
    - name: |
        su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='{{ postgresql_database }}'\"" | grep -q 1 \
          || su - postgres -c "createdb -O {{ postgresql_user }} {{ postgresql_database }}"
    - shell: /bin/bash
    - require:
      - cmd: openbao_postgresql_user
{% endif %}
{% endif %}

{% if pillar["openbao"].get("tls", {}).get("self_signed", {}).get("enable", False) %}
  {% set tls_cfg = pillar["openbao"]["tls"]["self_signed"] %}
  {% set tls_common_name = tls_cfg.get("common_name", grains["fqdn"]) %}
  {% set tls_san = tls_cfg.get("subject_alt_name", "DNS:" ~ tls_common_name ~ ",DNS:localhost,IP:127.0.0.1") %}

openbao_tls_dir:
  file.directory:
    - name: {{ tls_dir }}
    - user: openbao
    - group: openbao
    - dir_mode: 750
    - makedirs: True
    - require:
      - user: openbao_user

openbao_self_signed_tls:
  cmd.run:
    - name: openssl req -x509 -newkey rsa:4096 -sha256 -days {{ tls_cfg.get("days", 3650) }} -nodes -keyout {{ tls_dir }}/tls.key -out {{ tls_dir }}/tls.crt -subj "/CN={{ tls_common_name }}" -addext "subjectAltName={{ tls_san }}"
    - unless: test -s {{ tls_dir }}/tls.crt && test -s {{ tls_dir }}/tls.key && openssl x509 -in {{ tls_dir }}/tls.crt -noout -subject 2>/dev/null | grep -q "CN *= *{{ tls_common_name }}"
    - require:
      - file: openbao_tls_dir

openbao_self_signed_tls_permissions:
  cmd.run:
    - name: chmod 0640 {{ tls_dir }}/tls.key && chmod 0644 {{ tls_dir }}/tls.crt && chown -R openbao:openbao {{ tls_dir }}
    - require:
      - cmd: openbao_self_signed_tls
{% endif %}

{% if pillar["acme"] is defined and pillar["openbao"].get("acme", {}).get("enable", False) and pillar["openbao"]["acme"].get("domain") is defined %}
  {% set acme_account = pillar["acme"].keys() | first %}

    {{ verify_and_issue(acme_account, "openbao", pillar["openbao"]["acme"]["domain"]) }}

openbao_cert_permissions:
  cmd.run:
    - name: /usr/bin/chown openbao:openbao /opt/acme/cert/openbao_{{ pillar["openbao"]["acme"]["domain"] }}*

openbao_cert_permissions_cron:
  cron.present:
    - name: /usr/bin/chown openbao:openbao /opt/acme/cert/openbao_{{ pillar["openbao"]["acme"]["domain"] }}*
    - identifier: set permissions for openbao certificate
    - user: root
    - minute: 0
{% endif %}

{% if pillar["openbao"].get("seal", {}).get("static", {}).get("enable", False) %}
  {% set static_key_file = pillar["openbao"]["seal"]["static"].get("key_file", seal_dir ~ "/static-unseal.key") %}

openbao_static_seal_dir:
  file.directory:
    - name: {{ seal_dir }}
    - user: openbao
    - group: openbao
    - dir_mode: 750
    - makedirs: True
    - require:
      - file: openbao_config_dir

openbao_static_seal_key:
  cmd.run:
    - name: umask 077 && printf "%s" "$(openssl rand -hex 32)" > {{ static_key_file }} && chown openbao:openbao {{ static_key_file }}
    - unless: test -f {{ static_key_file }} && test "$(wc -c < {{ static_key_file }})" -eq 64
    - require:
      - file: openbao_static_seal_dir
{% endif %}

openbao_config:
  file.managed:
    - name: {{ config_dir }}/openbao.hcl
    - mode: 640
    - user: openbao
    - group: openbao
    - contents: |
        {{ pillar["openbao"]["config"] | indent(8) }}
    - require:
      - file: openbao_config_dir

openbao_env_file:
  file.managed:
    - name: {{ config_dir }}/openbao.env
    - mode: 640
    - user: openbao
    - group: openbao
    - contents: |
    {%- for var_key, var_val in pillar["openbao"].get("env_vars", {}).items() %}
        {{ var_key }}={{ var_val }}
    {%- endfor %}
    - require:
      - file: openbao_config_dir

openbao_set_environment:
  file.replace:
    - name: /etc/environment
    - pattern: '^ *BAO_ADDR=.*$'
    - repl: 'BAO_ADDR={{ pillar["openbao"].get("env_vars", {}).get("BAO_ADDR", "https://127.0.0.1:8200") }}'
    - append_if_not_found: True

openbao_systemd_override_dir:
  file.directory:
    - name: /etc/systemd/system/openbao.service.d
    - dir_mode: 755
    - makedirs: True

openbao_systemd_override:
  file.managed:
    - name: /etc/systemd/system/openbao.service.d/microdevops.conf
    - mode: 644
    - user: root
    - group: root
    - contents: |
        [Service]
        EnvironmentFile={{ config_dir }}/openbao.env
        ExecStart=
        ExecStart=/usr/bin/bao server -config={{ config_dir }}
        CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK CAP_NET_BIND_SERVICE
        AmbientCapabilities=CAP_IPC_LOCK CAP_NET_BIND_SERVICE
        LimitCORE=0
        LimitMEMLOCK=infinity
    - require:
      - file: openbao_systemd_override_dir

openbao_enable_capabilities:
  cmd.run:
    - name: setcap cap_ipc_lock,cap_net_bind_service=+ep /usr/bin/bao || true
    - require:
      - cmd: openbao_package_install

openbao_systemd_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: openbao_systemd_override

openbao_reset_failed:
  cmd.run:
    - name: systemctl reset-failed openbao || true
    - require:
      - cmd: openbao_systemd_daemon_reload

openbao_service_enable_and_start:
  service.running:
    - name: openbao
    - enable: true
    - require:
      - cmd: openbao_package_install
      - file: openbao_config
      - file: openbao_env_file
      - cmd: openbao_systemd_daemon_reload
      - cmd: openbao_reset_failed
{% if setup_postgresql %}
{% if postgresql_password is none %}
      - cmd: openbao_postgresql_password_missing
{% else %}
      - cmd: openbao_postgresql_database
{% endif %}
{% endif %}
{% if pillar["openbao"].get("tls", {}).get("self_signed", {}).get("enable", False) %}
      - cmd: openbao_self_signed_tls_permissions
{% endif %}
{% if pillar["openbao"].get("seal", {}).get("static", {}).get("enable", False) %}
      - cmd: openbao_static_seal_key
{% endif %}

openbao_service_restart:
  cmd.run:
    - name: sleep 5; systemctl restart openbao
    - onchanges:
      - file: {{ config_dir }}/openbao.hcl
      - file: {{ config_dir }}/openbao.env
      - file: /etc/systemd/system/openbao.service.d/microdevops.conf
      - cmd: openbao_package_install
{% if pillar["openbao"].get("seal", {}).get("static", {}).get("enable", False) %}
      - cmd: openbao_static_seal_key
{% endif %}
{% if pillar["openbao"].get("tls", {}).get("self_signed", {}).get("enable", False) %}
      - cmd: openbao_self_signed_tls_permissions
{% endif %}

{% if pillar["openbao"].get("snapshots", {}).get("enable_postgresql", False) %}
  {% set snapshots_dir = pillar["openbao"]["snapshots"].get("dir", "/opt/openbao/snapshots") %}
  {% set cron_minute = pillar["openbao"]["snapshots"].get("cron_minute", range(6, 54) | random) %}
  {% set cron_hour = pillar["openbao"]["snapshots"].get("cron_hour", "*/4") %}
  {% set cron_daymonth = pillar["openbao"]["snapshots"].get("cron_daymonth", "*") %}
  {% set cron_month = pillar["openbao"]["snapshots"].get("cron_month", "*") %}
  {% set cron_dayweek = pillar["openbao"]["snapshots"].get("cron_dayweek", "*") %}

openbao_create_snapshots_directory:
  file.directory:
    - name: {{ snapshots_dir }}
    - user: openbao
    - group: openbao
    - dir_mode: 750
    - file_mode: 600
    - makedirs: True

openbao_postgresql_snapshot_script:
  file.managed:
    - name: /opt/openbao/snapshot-postgresql.sh
    - mode: 750
    - user: root
    - group: root
    - contents: |
        #!/bin/bash
        set -euo pipefail
        timestamp=$(date +'%y-%m-%d_%H-%M-%S')
        snapshots_dir={{ snapshots_dir }}
        find "$snapshots_dir" -type f -mtime +{{ pillar["openbao"]["snapshots"].get("retention", 7) }} -delete
        su - postgres -c "pg_dump {{ postgresql_database }}" > "$snapshots_dir/openbao_${timestamp}.sql"
        chmod 0600 "$snapshots_dir/openbao_${timestamp}.sql"

openbao_postgresql_snapshot_cron:
  cron.present:
    - name: /opt/openbao/snapshot-postgresql.sh
    - identifier: openbao_postgresql_snapshot
    - minute: '{{ cron_minute }}'
    - hour: '{{ cron_hour }}'
    - daymonth: '{{ cron_daymonth }}'
    - month: '{{ cron_month }}'
    - dayweek: '{{ cron_dayweek }}'
    - user: root
{% endif %}

{% endif %}
