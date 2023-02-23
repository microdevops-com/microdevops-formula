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

  {% if pillar["vault"]["acme_account"] is defined %}
vault_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["vault"]["acme_account"] }}/verify_and_issue.sh vault {{ pillar["vault"]["name"] }} || true"

cert_permissions:
  cmd.run:
    - name: /usr/bin/chown -R vault:vault  /opt/acme/cert/{{ pillar["vault"]["name"] }}/*
  {% endif %}
vault_data_dir:
  file.directory:
    - names:
      - /opt/vault/data
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

  {% if pillar["vault"]["acme_account"] is defined %}
cert_permissions_cron:
  cron.present:
    - name: /usr/bin/chown vault:vault -R /opt/acme/cert/{{ pillar["vault"]["name"] }}/*
    - identifier: set permissions for vault certificate
    - user: root
    - minute: 0
    - hour: 1
  {% endif %} 

vault_service_enable_and_start:
  service.running:
    - name: vault
    - enable: true

vault_restart:
  cmd.run:
    - name: sleep 5; systemctl restart vault
    - onchanges:
        - file: /etc/vault.d/vault.hcl

{% endif %}
