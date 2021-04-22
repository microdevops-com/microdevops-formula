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

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;

        events {
            worker_connections 8192;
        }

        http {
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar["onlyoffice"]["domains"] %}

            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                ssl_certificate /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/onlyoffice_{{ domain["name"] }}_key.key;

                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }}/;
                    include    proxy_params;
                }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["onlyoffice"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "openssl verify -CAfile /opt/acme/cert/onlyoffice_{{ domain["name"] }}_ca.cer /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_cert.cer --key-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_key.key --ca-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_ca.cer --fullchain-file /opt/acme/cert/onlyoffice_{{ domain["name"] }}_fullchain.cer --issue -d {{ domain["name"] }} || true"

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
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:80/tcp
    - client_timeout: 120
    - environment:
    {%- if "env_vars" in domain %}
      {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}
    {%- endif %}

  {%- endfor %}

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

{% endif %}
