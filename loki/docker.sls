{% if pillar['loki'] is defined and pillar['loki'] is not none %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": "latest",
                         "daemon_json": '{ "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

basic_auth:
  webutil.user_exists:
    - name: {{ pillar["loki"]["auth_basic"]["username"] }}
    - password: {{ pillar["loki"]["auth_basic"]["password"] }}
    - htpasswd_file: /etc/nginx/htpasswd

  {% if pillar["loki"]["separated_nginx_config"] is defined and pillar["loki"]["separated_nginx_config"] %}
nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/loki.conf
    - contents: |
        server {
            listen 443 ssl;
            server_name {{ pillar["loki"]["name"] }};
            ssl_certificate /opt/acme/cert/loki_{{ pillar["loki"]["name"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/loki_{{ pillar["loki"]["name"] }}_key.key;
            auth_basic "Administrator’s Area";
            auth_basic_user_file /etc/nginx/htpasswd;
            location / {
                proxy_connect_timeout       {{ pillar["loki"]["timeout"] | default(300) }};
                proxy_send_timeout          {{ pillar["loki"]["timeout"] | default(300) }};
                proxy_read_timeout          {{ pillar["loki"]["timeout"] | default(300) }};
                send_timeout                {{ pillar["loki"]["timeout"] | default(300) }};
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $remote_addr;
                proxy_set_header Host $http_host;
                proxy_set_header Upgrade websocket;
                proxy_set_header Connection Upgrade;
                proxy_pass http://localhost:{{ pillar["loki"]["config"]["server"]["http_listen_port"] }}/;
            }
        }
  file.symlink:
    - name: /etc/nginx/sites-enabled/loki.conf
    - target: /etc/nginx/sites-available/loki.conf
  {% else %}
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
            map $http_upgrade $connection_upgrade {
                default upgrade;
                '' close;
            }
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
            server {
                listen 443 ssl;
                server_name {{ pillar["loki"]["name"] }};
                ssl_certificate /opt/acme/cert/loki_{{ pillar["loki"]["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/loki_{{ pillar["loki"]["name"] }}_key.key;
                auth_basic "Administrator’s Area";
                auth_basic_user_file /etc/nginx/htpasswd;
                location / {
                    proxy_connect_timeout       {{ pillar["loki"]["timeout"] | default(300) }};
                    proxy_send_timeout          {{ pillar["loki"]["timeout"] | default(300) }};
                    proxy_read_timeout          {{ pillar["loki"]["timeout"] | default(300) }};
                    send_timeout                {{ pillar["loki"]["timeout"] | default(300) }};
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header X-Forwarded-For $remote_addr;
                    proxy_set_header Host $http_host;
                    proxy_set_header Upgrade websocket;
                    proxy_set_header Connection Upgrade;
                    proxy_pass http://localhost:{{ pillar["loki"]["config"]["server"]["http_listen_port"] }}/;
                }
            }
        }
  {% endif %}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["loki"]["acme_account"] }}/verify_and_issue.sh loki {{ pillar["loki"]["name"] }}"

loki_data_dir:
  file.directory:
    - names:
      - /opt/loki/{{ pillar['loki']['name'] }}
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

loki_config:
  file.serialize:
    - name: /opt/loki/{{ pillar['loki']['name'] }}/config.yaml
    - user: 0
    - group: 0
    - mode: 644
    - serializer: yaml
    - dataset_pillar: loki:config
    - serializer_opts:
      - sort_keys: False
 
loki_image:
  cmd.run:
    - name: docker pull {{ pillar['loki']['image'] }}

loki_container:
  docker_container.running:
    - name: loki-{{ pillar['loki']['name'] }}
    - user: root
    - image: {{ pillar['loki']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ pillar['loki']['config']['server']['http_listen_port'] }}:{{ pillar['loki']['config']['server']['http_listen_port'] }}/tcp
    - binds:
        - /opt/loki/{{ pillar['loki']['name'] }}:{{ pillar['loki']['path_prefix'] }}
    - watch:
        - /opt/loki/{{ pillar['loki']['name'] }}/config.yaml
    - command: -config.file={{ pillar['loki']['path_prefix'] }}/config.yaml

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
