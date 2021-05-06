{% if pillar["xwiki"] is defined %}
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
        - docker-ce: '{{ pillar["xwiki"]["docker-ce_version"] }}*'
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
            use epoll;
            multi_accept on;
        }

        http {
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            tcp_nopush on;
            tcp_nodelay on;
            gzip on;
            gzip_comp_level 4;
            gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
            gzip_vary on;
            gzip_proxied any;
            client_max_body_size 1000m;
            
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar["xwiki"]["domains"] %}

            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                ssl_certificate /opt/acme/cert/xwiki_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/xwiki_{{ domain["name"] }}_key.key;

                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }}/;
                    include    proxy_params;
                    add_header Content-Security-Policy upgrade-insecure-requests;
                }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["xwiki"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "openssl verify -CAfile /opt/acme/cert/xwiki_{{ domain["name"] }}_ca.cer /opt/acme/cert/xwiki_{{ domain["name"] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/xwiki_{{ domain["name"] }}_cert.cer --key-file /opt/acme/cert/xwiki_{{ domain["name"] }}_key.key --ca-file /opt/acme/cert/xwiki_{{ domain["name"] }}_ca.cer --fullchain-file /opt/acme/cert/xwiki_{{ domain["name"] }}_fullchain.cer --issue -d {{ domain["name"] }} || true"

xwiki_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/xwiki/{{ domain["name"] }}/data
    - mode: 755
    - makedirs: True

xwiki_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

xwiki_container_{{ loop.index }}:
  docker_container.running:
    - name: xwiki-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:8080/tcp
    - binds:
        - /opt/xwiki/{{ domain["name"] }}/data:/usr/local/xwiki/data:rw
    {%- if "env_vars" in domain %}
    - environment:
      {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}
    {%- endif %}

wait_for_container_{{ loop.index }}:
  cmd.run:
    - name: sleep {{ domain["container_start_timeout"] }}

xwiki_validationkey_{{ loop.index }}:
    file.replace:
      - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'
      - pattern: '^ *(xwiki.authentication.validationKey=).*$'
      - repl: '\1{{ domain["validationkey"] }}'

xwiki_encryptionkey_{{ loop.index }}:
    file.replace:
      - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'
      - pattern: '^ *(xwiki.authentication.encryptionKey=).*$'
      - repl: '\1{{ domain["encryptionkey"] }}'

xwiki_container_restart_{{ loop.index }}:
  cmd.run:
    - name: docker stop xwiki-{{ domain["name"] }} && docker start xwiki-{{ domain["name"] }}
    - onchanges:
        - file: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'

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
