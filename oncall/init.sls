{% if pillar["oncall"] is defined and pillar["docker-ce"] is defined %}

oncall_data_dirs:
  file.directory:
    - names:
      - /opt/oncall/volumes/oncall
      - /opt/oncall/volumes/redis
      - /opt/oncall/cert
      - /opt/oncall/public
    - makedirs: True

  {% if pillar["acme"] is defined %}

    {% from "acme/macros.jinja" import verify_and_issue %}

    {% set acme = pillar["acme"].keys() | first %}

    {{ verify_and_issue(acme, "oncall", pillar["oncall"]["domain"]) }}

  {% else %}

generate_self_signed_cert_with_check_expire:
  cmd.run:
    - name: openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_key.key -out /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_fullchain.cer -subj "{{ pillar["oncall"]["self_signed_cert_subject"] }}"
    - unless: openssl x509 -checkend 86400 -noout -in /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_fullchain.cer

  {% endif %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["oncall"]["nginx_sites_enabled"] | default(false) %}
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

create /etc/nginx/sites-available/{{ pillar["oncall"]["domain"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["oncall"]["domain"] }}.conf
    - contents: |
        upstream {{ pillar["oncall"]["domain"] | replace(".","_") }} {
          server 127.0.0.1:8080;
          keepalive 4;
        }
        server {
          listen 80;
          server_name {{ pillar["oncall"]["domain"] }};
          return 301 https://$host$request_uri;
        }
        server {
          listen 443 ssl http2;
          server_name {{ pillar["oncall"]["domain"] }};
          {% if pillar["acme"] is defined %}
          ssl_certificate /opt/acme/cert/oncall_{{ pillar["oncall"]["domain"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/oncall_{{ pillar["oncall"]["domain"] }}_key.key;
          {% else %}
          ssl_certificate /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_fullchain.cer;
          ssl_certificate_key /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_key.key;
          {% endif %}
          root /opt/oncall/public;
          charset UTF-8;
          autoindex off;

          client_max_body_size   128M;
          proxy_connect_timeout  120;
          proxy_send_timeout     120;
          proxy_read_timeout     120;
          send_timeout           120;

          location / {
            proxy_http_version 1.1;
            proxy_set_header "Connection" "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://{{ pillar["oncall"]["domain"] | replace(".","_") }};
          }
        }

create symlink /etc/nginx/sites-enabled/{{ pillar["oncall"]["domain"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["oncall"]["domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["oncall"]["domain"] }}.conf
    - force: True

delete /etc/nginx/sites-enabled/default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
  
  {%- else %}

nginx_files_1:
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
          upstream {{ pillar["oncall"]["domain"] | replace(".","_") }} {
            server 127.0.0.1:8080;
            keepalive 4;
          }
          server {
            listen 80;
            server_name {{ pillar["oncall"]["domain"] }};
            return 301 https://$host$request_uri;
          }
          server {
            listen 443 ssl http2;
            server_name {{ pillar["oncall"]["domain"] }};
            {% if pillar["acme"] is defined %}
            ssl_certificate /opt/acme/cert/oncall_{{ pillar["oncall"]["domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/oncall_{{ pillar["oncall"]["domain"] }}_key.key;
            {% else %}
            ssl_certificate /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/oncall/cert/oncall_{{ pillar["oncall"]["domain"] }}_key.key;
            {% endif %}
            root /opt/oncall/public;
            charset UTF-8;
            autoindex off;

            client_max_body_size   128M;
            proxy_connect_timeout  120;
            proxy_send_timeout     120;
            proxy_read_timeout     120;
            send_timeout           120;

            location / {
              proxy_http_version 1.1;
              proxy_set_header "Connection" "";
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_pass http://{{ pillar["oncall"]["domain"] | replace(".","_") }};
            }
          }
        }
  {%- endif %}

download_docker-compose_file:
  cmd.run:
    - name: curl -fsSL https://raw.githubusercontent.com/grafana/oncall/dev/docker-compose.yml -o /opt/oncall/docker-compose.yml

fix_docker-compose_file:
  cmd.run:
    - name: sed -i 's|- "8080:8080"|- "127.0.0.1:8080:8080"|' /opt/oncall/docker-compose.yml

make_docker-compose_override:
  file.managed:
    - name: /opt/oncall/docker-compose.override.yml
    - contents: |
        services:
          engine:
            image: grafana/oncall:${ONCALL_VERSION}
            ports:
              - "127.0.0.1:8080:8080"
            env_file:
              - .env
          celery:
            image: grafana/oncall:${ONCALL_VERSION}
            env_file:
              - .env
          oncall_db_migration:
            image: grafana/oncall:${ONCALL_VERSION}
            env_file:
              - .env
        volumes:
          oncall_data:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/oncall'
          redis_data:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/redis'

dotenv:
  file.managed:
    - name: /opt/oncall/.env
    - contents: |
        {%- for key, value in pillar["oncall"]["env_vars"].items() %}
        {{ key }}={{ value }}
        {%- endfor %}

docker_compose_up:
  cmd.run:
    - name: docker-compose -f /opt/oncall/docker-compose.yml -f /opt/oncall/docker-compose.override.yml up -d
    - cwd: /opt/oncall

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
