{% if pillar["collabora"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

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
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          sendfile on;
          keepalive_timeout 65;
            server {
              listen 80;
              return 301 https://$host$request_uri;
            }
  {%- for domain in pillar["collabora"]["domains"] %}
            upstream {{ domain["internal_name"] }} {
              server 127.0.0.1:{{ domain["internal_port"] }};
            }
            server {
              listen 443 ssl;
              server_name {{ domain["name"] }};
              ssl_certificate /opt/acme/cert/collabora_{{ domain["name"] }}_fullchain.cer;
              ssl_certificate_key /opt/acme/cert/collabora_{{ domain["name"] }}_key.key;
              # static files
              location ^~ /browser {
               proxy_pass http://{{ domain["internal_name"] }};
               proxy_set_header Host $http_host;
              }
              # WOPI discovery URL
              location ^~ /hosting/discovery {
               proxy_pass http://{{ domain["internal_name"] }};
               proxy_set_header Host $http_host;
              }
              # Capabilities
              location ^~ /hosting/capabilities {
               proxy_pass http://{{ domain["internal_name"] }};
               proxy_set_header Host $http_host;
              }
              # main websocket
              location ~ ^/cool/(.*)/ws$ {
               proxy_pass http://{{ domain["internal_name"] }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
              # download, presentation and image upload
              location ~ ^/(c|l)ool {
               proxy_pass http://{{ domain["internal_name"] }};
               proxy_set_header Host $http_host;
              }
              # Admin Console websocket
              location ^~ /cool/adminws {
               proxy_pass http://{{ domain["internal_name"] }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["collabora"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh collabora {{ domain["name"] }}"

collabora_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

collabora_container_{{ loop.index }}:
  docker_container.running:
    - name: collabora-{{ domain["name"] }}
    - user: cool
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - cap_add: MKNOD
    - privileged: True
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:9980/tcp
    - environment:
        - extra_params: --o:ssl.enable=false --o:ssl.termination=true
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
