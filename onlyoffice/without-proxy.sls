{% if pillar["onlyoffice"] is defined %}
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

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: '{{ pillar["onlyoffice"]["docker-ce_version"] }}*'
        - python3-pip

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
        {%- for domain in pillar["onlyoffice"]["domains"] %}
cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "openssl verify -CAfile /opt/acme/cert/onlyoffice_{{ domain["name"] }}_ca.cer /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_cert.cer --key-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_key.key --ca-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_ca.cer --fullchain-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer --issue -d {{ domain["name"] }} || true"

onlyoffice_data_folder_{{ loop.index }}:
  file.directory:
    - names:
      - /opt/onlyoffice/{{ domain["name"] }}/var/log/onlyoffice/
      - /opt/onlyoffice/{{ domain["name"] }}/var/www/onlyoffice/Data/
      - /opt/onlyoffice/{{ domain["name"] }}/var/lib/onlyoffice/
      - /opt/onlyoffice/{{ domain["name"] }}/var/lib/postgresql/
    - mode: 755
    - makedirs: True
onlyoffice_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

onlyoffice_container_{{ loop.index }}:
  docker_container.running:
    - name: onlyoffice-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
        - /opt/acme/cert/:/opt/acme:ro
        - /opt/onlyoffice/{{ domain["name"] }}/var/log/onlyoffice:/var/log/onlyoffice:rw
        - /opt/onlyoffice/{{ domain["name"] }}/var/www/onlyoffice/Data:/var/www/onlyoffice/Data:rw
        - /opt/onlyoffice/{{ domain["name"] }}/var/lib/onlyoffice:/var/lib/onlyoffice:rw
        - /opt/onlyoffice/{{ domain["name"] }}/var/lib/postgresql:/var/lib/postgresql:rw
    - publish:
        - 80:80/tcp
        - 443:443/tcp
    - client_timeout: 120
    {%- if "env_vars" in domain %}
    - environment:
      {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}
    {%- endif %}
  {%- endfor %}
{% endif %}
