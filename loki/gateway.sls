{% if pillar['loki'] is defined and pillar["acme"] is defined %}
{%- if pillar["loki"]["nginx_gateway"] | default(false) %}
{% set acme = pillar['acme'].keys() | first %}
nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

{% if "separated_nginx_config" in pillar["loki"] and pillar["loki"]["separated_nginx_config"] %}
nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites_available/loki.conf
    - contents: |
        upstream read {
  {%- for reader in pillar["loki"]["readers"] %}
          server {{ reader }} max_fails=1 fail_timeout=10;
  {%- endfor %}
        }
        upstream write {
  {%- for writer in pillar["loki"]["writers"] %}
          server {{ writer }} max_fails=1 fail_timeout=10;
  {%- endfor %}
        }
        upstream cluster {
  {%- for reader in pillar["loki"]["readers"] %}
          server {{ reader }} max_fails=1 fail_timeout=10;
  {%- endfor %}
  {%- for writer in pillar["loki"]["writers"] %}
          server {{ writer }} max_fails=1 fail_timeout=10;
  {%- endfor %}
        }
        upstream query-frontend {
  {%- for query_frontend in pillar["loki"]["query_frontends"] %}
          server {{ query_frontend }} max_fails=1 fail_timeout=10;
  {%- endfor %}
        }
        server {
          listen 80;
          return 301 https://$host$request_uri;
        }
        server {
          listen 443 ssl;
          listen 3100 ssl;
          ssl_certificate /opt/acme/cert/{{ pillar["loki"]["name"] }}/fullchain.cer;
          ssl_certificate_key /opt/acme/cert/{{ pillar["loki"]["name"] }}/{{ pillar["loki"]["name"] }}.key;
          location = /ring {
              proxy_pass       http://cluster$request_uri;
          }
          location = /memberlist {
              proxy_pass       http://cluster$request_uri;
          }
          location = /config {
              proxy_pass       http://cluster$request_uri;
          }
          location = /metrics {
              proxy_pass       http://cluster$request_uri;
          }
          location = /ready {
              proxy_pass       http://cluster$request_uri;
          }
          location = /loki/api/v1/push {
              proxy_pass       http://write$request_uri;
          }
          location = /loki/api/v1/tail {
             proxy_pass       http://read$request_uri;
             proxy_set_header Upgrade $http_upgrade;
             proxy_set_header Connection "upgrade";
          }
          location ~ /loki/api/.* {
             proxy_pass       http://query-frontend$request_uri;
          }
        }
        server {
          listen 3101 ssl;
          ssl_certificate /opt/acme/cert/{{ pillar["loki"]["name"] }}/fullchain.cer;
          ssl_certificate_key /opt/acme/cert/{{ pillar["loki"]["name"] }}/{{ pillar["loki"]["name"] }}.key;
          location / {
              proxy_pass       http://write$request_uri;
          }
        }
nginx_symlink_1:
  file.symlink:
    - name: /etc/nginx/sites-enabled/loki.conf
    - target: /etc/nginx/sites-available/loki.conf
{% else %}
nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_rlimit_nofile 8192;
        events {
            worker_connections  4096;  ## Default: 1024
        }
        http {
          default_type application/octet-stream;
          log_format   main '$remote_addr - $remote_user [$time_local]  $status '
            '"$request" $body_bytes_sent "$http_referer" '
            '"$http_user_agent" "$http_x_forwarded_for"';
          sendfile     on;
          tcp_nopush   on;
                proxy_connect_timeout      {{ pillar["loki"]["timeout"] }};
                proxy_send_timeout         {{ pillar["loki"]["timeout"] }};
                proxy_read_timeout         {{ pillar["loki"]["timeout"] }};
                send_timeout               {{ pillar["loki"]["timeout"] }};
          upstream read {
  {%- for reader in pillar["loki"]["readers"] %}
            server {{ reader }} max_fails=1 fail_timeout=10;
  {%- endfor %}
          }
          upstream write {
  {%- for writer in pillar["loki"]["writers"] %}
            server {{ writer }} max_fails=1 fail_timeout=10;
  {%- endfor %}
          }
          upstream cluster {
  {%- for reader in pillar["loki"]["readers"] %}
            server {{ reader }} max_fails=1 fail_timeout=10;
  {%- endfor %}
  {%- for writer in pillar["loki"]["writers"] %}
            server {{ writer }} max_fails=1 fail_timeout=10;
  {%- endfor %}
          }
          upstream query-frontend {
  {%- for query_frontend in pillar["loki"]["query_frontends"] %}
            server {{ query_frontend }} max_fails=1 fail_timeout=10;
  {%- endfor %}
          }
          server {
            listen 80;
            return 301 https://$host$request_uri;
          }
          server {
            listen 443 ssl;
            listen 3100 ssl;
            ssl_certificate /opt/acme/cert/{{ pillar["loki"]["name"] }}/fullchain.cer;
            ssl_certificate_key /opt/acme/cert/{{ pillar["loki"]["name"] }}/{{ pillar["loki"]["name"] }}.key;
            location = /ring {
                proxy_pass       http://cluster$request_uri;
            }
            location = /memberlist {
                proxy_pass       http://cluster$request_uri;
            }
            location = /config {
                proxy_pass       http://cluster$request_uri;
            }
            location = /metrics {
                proxy_pass       http://cluster$request_uri;
            }
            location = /ready {
                proxy_pass       http://cluster$request_uri;
            }
            location = /loki/api/v1/push {
                proxy_pass       http://write$request_uri;
            }
            location = /loki/api/v1/tail {
               proxy_pass       http://read$request_uri;
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "upgrade";
            }
            location ~ /loki/api/.* {
               proxy_pass       http://query-frontend$request_uri;
            }
          }
          server {
            listen 3101 ssl;
            ssl_certificate /opt/acme/cert/{{ pillar["loki"]["name"] }}/fullchain.cer;
            ssl_certificate_key /opt/acme/cert/{{ pillar["loki"]["name"] }}/{{ pillar["loki"]["name"] }}.key;
            location / {
                proxy_pass       http://write$request_uri;
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
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh loki-gateway {{ pillar["loki"]["name"] }}"

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx restart

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx restart
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
{%- endif %}
{%- endif %}
