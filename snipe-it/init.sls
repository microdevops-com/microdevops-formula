{% if pillar["snipe-it"] is defined %}
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
        - docker-ce: "{{ pillar["snipe-it"]["docker-ce_version"] }}*"
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
  {%- for domain in pillar["snipe-it"]["domains"] %}
            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                ssl_certificate /opt/acme/cert/snipe-it_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/snipe-it_{{ domain["name"] }}_key.key;
                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }}/;
                    include    proxy_params;
                    proxy_set_header X-Forwarded-Proto $scheme;
                }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["snipe-it"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ domain["acme_account"] }}/verify_and_issue.sh snipe-it {{ domain["name"] }}"

snipe-it_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/snipe-it/{{ domain["name"] }}/data/var/lib/snipeit/
    - mode: 755
    - makedirs: True

snipe-it_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}
snipe-it_container_{{ loop.index }}:
  docker_container.running:
    - name: snipe-it-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:80/tcp
    - binds:
        - /opt/snipe-it/{{ domain["name"] }}/data/var/lib/snipeit:/var/lib/snipeit:rw
    - environment:
    {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
    {%- endfor %}
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
