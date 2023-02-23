{% if pillar["vault"] is defined %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains["os"]|lower }} {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains["os"]|lower }}/gpg

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
        - docker-ce: "{{ pillar["vault"]["docker-ce_version"] }}*"
        - python3-pip
        - vault

vault_autocomplete_install:
  cmd.run:
    - name: vault -autocomplete-install || true

docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True

docker_install_3:
  service.running:
    - name: docker

docker_install_4:
  cmd.run:
    - name: systemctl restart docker
    - onchanges:
        - file: /etc/docker/daemon.json

vault_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["vault"]["acme_account"] }}/verify_and_issue.sh vault {{ pillar["vault"]["name"] }} || true"

cert_permissions:
  cmd.run:
    - name: /usr/bin/chown 100:1000  /opt/acme/cert/*

vault_data_dir:
  file.directory:
    - names:
      - /opt/vault/{{ pillar["vault"]["name"] }}/data
      - /opt/vault/{{ pillar["vault"]["name"] }}/config
      - /opt/vault/{{ pillar["vault"]["name"] }}/logs
    - mode: 755
    - user: 100 
    - group: 1000
    - makedirs: True

vault_config:
  file.managed:
    - name: /opt/vault/{{ pillar["vault"]["name"] }}/config/config.hcl
    - contents: |
        {{ pillar["vault"]["config"] | indent(8) }}

vault_image:
  cmd.run:
    - name: docker pull {{ pillar["vault"]["image"] }}

vault_container:
  docker_container.running:
    - name: vault-{{ pillar["vault"]["name"] }}
    - user: root
    - image: {{ pillar["vault"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
      - 0.0.0.0:8200:8200/tcp
      - 0.0.0.0:8201:8201/tcp
    - binds:
      - /opt/vault/{{ pillar["vault"]["name"] }}/config/:/vault/config:rw
      - /opt/vault/{{ pillar["vault"]["name"] }}/data/:/vault/data:rw
      - /opt/vault/{{ pillar["vault"]["name"] }}/logs/:/vault/logs:rw
      - /opt/acme/cert:/vault/certs:rw
    - cap_add: IPC_LOCK
    - command: server
    - environment:
    {%- for var_key, var_val in pillar["vault"]["env_vars"].items() %}
      - {{ var_key }}: {{ var_val }}
    {%- endfor %}

vault_set_environment:
  file.replace:
    - name: '/etc/environment'
    - pattern: '^ *VAULT_ADDR=.*$'
    - repl: 'VAULT_ADDR={{ pillar["vault"]["env_vars"]["VAULT_ADDR"] }}'
    - append_if_not_found: True

cert_permissions_cron:
  cron.present:
    - name: /usr/bin/chown 100:1000 -R /opt/acme/cert/*
    - identifier: set permissions for vault certificate
    - user: root
    - minute: 0
    - hour: 1

container_restart:
  cmd.run:
    - name: sleep 5; docker restart vault-{{ pillar["vault"]["name"] }}
    - onchanges:
        - file: /opt/vault/{{ pillar["vault"]["name"] }}/config/config.hcl

{% endif %}
