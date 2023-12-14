{% if pillar["authentik"] is defined and pillar["acme"] is defined and pillar["docker-ce"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["authentik"]["nginx_sites_enabled"] | default(false) %}
create nginx.conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        #user www-data;
        worker_processes auto;
        worker_rlimit_nofile 40000;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {
            worker_connections 8192;
        }
        http {
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;
          types_hash_max_size 2048;
          server_names_hash_bucket_size 64;
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers on;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          gzip on;
          include /etc/nginx/conf.d/*.conf;
          include /etc/nginx/sites-enabled/*;
        }

create /etc/nginx/sites-available/{{ pillar["authentik"]["domain"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["authentik"]["domain"] }}.conf
    - contents: |
        upstream {{ pillar["authentik"]["domain"] | replace(".","_") }} {
          server 127.0.0.1:{{ pillar["authentik"]["internal_port_https"] | default(9443) }};
          keepalive 10;
        }
        # Upgrade WebSocket if requested, otherwise use keepalive
        map $http_upgrade $connection_upgrade_keepalive {
            default upgrade;
            ''      '';
        }
        server {
          listen 80;
          server_name {{ pillar["authentik"]["domain"] }};
          return 301 https://$host$request_uri;
        }
        server {
          listen 443 ssl;
          server_name {{ pillar["authentik"]["domain"] }};
          ssl_certificate /opt/acme/cert/authentik_{{ pillar["authentik"]["domain"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/authentik_{{ pillar["authentik"]["domain"] }}_key.key;
          location = /robots.txt {
            return 200 "User-agent: *\nDisallow: /\n";
          }
          location / {
            proxy_pass https://{{ pillar["authentik"]["domain"] | replace(".","_") }};
            proxy_http_version 1.1;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header Host              $host;
            proxy_set_header Upgrade           $http_upgrade;
            proxy_set_header Connection        $connection_upgrade_keepalive;
          }
        }

create symlink /etc/nginx/sites-enabled/{{ pillar["authentik"]["domain"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["authentik"]["domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["authentik"]["domain"] }}.conf
    - force: True

delete /etc/nginx/sites-enabled/default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
  
  {%- else %}

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
          # Upgrade WebSocket if requested, otherwise use keepalive
          map $http_upgrade $connection_upgrade_keepalive {
              default upgrade;
              ''      '';
          }
          server {
            listen 80;
            return 301 https://$host$request_uri;
          }
      
          upstream {{ pillar["authentik"]["domain"] | replace(".","_") }} {
            server 127.0.0.1:{{ pillar["authentik"]["internal_port_https"] | default(9443) }};
            keepalive 10;
          }
          server {
            listen 443 ssl;
            server_name {{ pillar["authentik"]["domain"] }};
            ssl_certificate /opt/acme/cert/authentik_{{ pillar["authentik"]["domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/authentik_{{ pillar["authentik"]["domain"] }}_key.key;
            location = /robots.txt {
              return 200 "User-agent: *\nDisallow: /\n";
            }
            location / {
              proxy_pass https://{{ pillar["authentik"]["domain"] | replace(".","_") }};
              proxy_http_version 1.1;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
              proxy_set_header Host              $host;
              proxy_set_header Upgrade           $http_upgrade;
              proxy_set_header Connection        $connection_upgrade_keepalive;
            }
          }
        }
  {%- endif %}

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/{{ acme }}/home/verify_and_issue.sh authentik {{ pillar["authentik"]["domain"] }}"

authentik_data_dirs:
  file.directory:
    - names:
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/redis-data
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/media
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/certs
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/custom-templates
    - makedirs: True

docker_network:
  docker_network.present:
    - name: authentik

redis_image:
  cmd.run:
    - name: docker pull docker.io/library/redis:alpine

authentik_image:
  cmd.run:
    - name: docker pull ghcr.io/goauthentik/server:{{ pillar["authentik"]["version"] }}

redis_container:
  docker_container.running:
    - name: redis-{{ pillar["authentik"]["domain"] }}
    - image: docker.io/library/redis:alpine
    - command: --save 60 1 --loglevel warning
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/redis-data:/data
    - networks:
      - authentik:
        - aliases:
          - redis

authentik_server_container:
  docker_container.running:
    - name: authentik-server-{{ pillar["authentik"]["domain"] }}
    - image: ghcr.io/goauthentik/server:{{ pillar["authentik"]["version"] }}
    - command: server
    - detach: True
    - restart_policy: unless-stopped
    - user: root
    - binds:
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/media:/media
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/custom-templates:/templates
    - publish:
      - {{ pillar["authentik"]["internal_port_http"]  | default(9000) }}:9000/tcp
      - {{ pillar["authentik"]["internal_port_https"] | default(9443) }}:9443/tcp
    - networks:
      - authentik:
        - aliases:
          - server
    - environment:
        - AUTHENTIK_REDIS__HOST: redis
    {%- for key, value in pillar["authentik"]["env_vars"].items() %}
        - {{ key }}: {{ value }}
    {%- endfor %}
    - require:
      - docker_container: redis-{{ pillar["authentik"]["domain"] }}

authentik_worker_container:
  docker_container.running:
    - name: authentik-worker-{{ pillar["authentik"]["domain"] }}
    - image: ghcr.io/goauthentik/server:{{ pillar["authentik"]["version"] }}
    - command: worker
    - detach: True
    - restart_policy: unless-stopped
    - user: root
    - binds:
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/media:/media
      - /opt/authentik/{{ pillar["authentik"]["domain"] }}/certs:/certs
      - /var/run/docker.sock:/var/run/docker.sock
    - environment:
        - AUTHENTIK_REDIS__HOST: redis
    {%- for key, value in pillar["authentik"]["env_vars"].items() %}
        - {{ key }}: {{ value }}
    {%- endfor %}
    - networks:
      - authentik:
        - aliases:
          - worker
    - require:
      - docker_container: redis-{{ pillar["authentik"]["domain"] }}

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