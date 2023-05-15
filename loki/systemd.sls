{% if pillar['loki'] is defined and pillar['loki'] is not none %}
  {% if pillar["loki"]["nginx_gateway"] | default(false) %}
    {% include "loki/gateway.sls" with context %}
  {% else %}

    {%- if pillar["loki"]["acme_configs"] is defined %}
      {% for acme_config in pillar["loki"]["acme_configs"] %}
ACME certificates issuing {{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/{{ acme_config["name"] }}/home/verify_and_issue.sh loki {%- for domain in acme_config["domains"] %} {{ domain }} {%- endfor -%}"
      {%- endfor%}
    {%- endif %}

{% if pillar["loki"]["nginx_revers_proxy"] | default(false) %}
nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

  {% if "auth_basic" in pillar["loki"]  %}
basic_auth:
  webutil.user_exists:
    - name: {{ pillar["loki"]["auth_basic"]["username"] }}
    - password: {{ pillar["loki"]["auth_basic"]["password"] }}
    - htpasswd_file: /etc/nginx/htpasswd
  {% endif %}

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

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

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

loki_dirs:
  file.directory:
    - names:
      - /opt/loki/etc
      - /opt/loki/bin
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

loki_config:
  file.serialize:
    - name: /opt/loki/etc/config.yaml
    - user: 0
    - group: 0
    - mode: 644
    - serializer: yaml
    - dataset_pillar: loki:config
    - serializer_opts:
      - sort_keys: False

loki_binary:
  archive.extracted:
    - name: /opt/loki/bin
    - source: {{ pillar['loki']['binary']['link'] }}
    - user: 0
    - group: 0
    - enforce_toplevel: False
    - skip_verify: True
  file.rename:
    - name: /opt/loki/bin/loki
    - source: /opt/loki/bin/loki-linux-amd64
    - force: True

loki_systemd_1:
  file.managed:
    - name: /etc/systemd/system/loki.service
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        [Unit]
        Description=Loki Service
        After=network.target
        [Service]
        Type=simple
        ExecStart=/opt/loki/bin/loki -config.file /opt/loki/etc/config.yaml {% if 'extra_args' in pillar['loki'] -%} {{ pillar['loki']['extra_args'] }} {%- endif %}
        ExecReload=/bin/kill -HUP $MAINPID
        Restart=on-failure
        [Install]
        WantedBy=multi-user.target

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/loki.service

loki_systemd_3:
  service.running:
    - name: loki
    - enable: True

loki_systemd_4:
  cmd.run:
    - name: systemctl restart loki
  {% endif %}
{% endif %}
