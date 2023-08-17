{% if pillar["rocketchat"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["rocketchat"]["nginx_sites_enabled"] | default(false) %}
create nginx.conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        user www-data;
        worker_processes auto;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {
          worker_connections 768;
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
    {%- for domain in pillar["rocketchat"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
        map $http_upgrade $connection_upgrade {
          default upgrade;
          ''      close;
        }
        {%- if pillar["rocketchat"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ domain["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
        upstream {{ domain["name"] | replace(".","_") }} {
          server 127.0.0.1:{{ domain["rocketchat"]["internal_port"] }};
        }
        server {
          listen {{ pillar["rocketchat"]["external_port"] | default(443) }} ssl;
          server_name {{ domain["name"] }};
          ssl_certificate /opt/acme/cert/rocketchat_{{ domain["name"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/rocketchat_{{ domain["name"] }}_key.key;
          client_max_body_size 200M;
          client_body_buffer_size 128k;
          location = /robots.txt {
            return 200 "User-agent: *\nDisallow: /\n";
          }
          location / {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
            proxy_set_header Host $http_host;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
          }
        }
create symlink /etc/nginx/sites-enabled/{{ domain["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ domain["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - force: True
    {%- endfor %}
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
          map $http_upgrade $connection_upgrade {
            default upgrade;
            ''      close;
          }
      {%- if pillar["rocketchat"]["external_port"] is not defined %}
          server {
            listen 80;
            return 301 https://$host$request_uri;
          }
      {%- endif %}
      {%- for domain in pillar["rocketchat"]["domains"] %}
          upstream {{ domain["name"] | replace(".","_") }} {
            server 127.0.0.1:{{ domain["rocketchat"]["internal_port"] }};
          }
          server {
            listen {{ pillar["rocketchat"]["external_port"] | default(443) }} ssl;
            server_name {{ domain["name"] }};
            ssl_certificate /opt/acme/cert/rocketchat_{{ domain["name"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/rocketchat_{{ domain["name"] }}_key.key;
            client_max_body_size 200M;
            client_body_buffer_size 128k;
            location = /robots.txt {
              return 200 "User-agent: *\nDisallow: /\n";
            }
            location / {
              proxy_pass http://{{ domain["name"] | replace(".","_") }};
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_http_version 1.1;
              proxy_set_header Host $http_host;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
            }
          }
    {%- endfor %}
        }
  {%- endif %}
delete /etc/nginx/sites-enabled/default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["rocketchat"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh rocketchat {{ domain["name"] }}"

rocketchat_data_subdir_{{ loop.index }}:
  file.directory:
    - names:
      - /opt/rocketchat/{{ domain["name"] }}/
    - makedirs: True

rocketchat_data_dir_{{ loop.index }}:
  file.directory:
    - names: 
      - /opt/rocketchat/{{ domain["name"] }}/mongodb
    - user: 1001
    - group: 1001

docker_network_{{ loop.index }}:
  docker_network.present:
    - name: {{ domain["name"] }}

mongodb_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["mongodb"]["image"] }}

mongodb_container_{{ loop.index }}:
  docker_container.running:
    - name: rocketchat-mongodb-{{ domain["name"] }}
    - image: {{ domain["mongodb"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
      - /opt/rocketchat/{{ domain["name"] }}/mongodb:/bitnami/mongodb
    - networks:
      - {{ domain["name"] }}
    - environment:
    {%- for var_key, var_val in domain["mongodb"]["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
    {%- endfor %}

rocketchat_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["rocketchat"]["image"] }}

rocketchat_container_{{ loop.index }}:
  docker_container.running:
    - name: rocketchat-{{ domain["name"] }}
    - image: {{ domain["rocketchat"]["image"] }}
    - detach: True
    - restart_policy: always
    - networks:
      - {{ domain["name"] }}
    - publish:
        - 127.0.0.1:{{ domain["rocketchat"]["internal_port"] }}:3000/tcp
    - labels:
    {%- for  label in domain["rocketchat"]["labels"] %}
        - {{ label }}
    {%- endfor %}
    - environment:
    {%- for var_key, var_val in domain["rocketchat"]["env_vars"].items() %}
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
