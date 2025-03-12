{% if pillar["keep"] is defined and pillar["acme"] is defined and pillar["docker-ce"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {% set acme = pillar["acme"].keys() | first %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["keep"]["nginx_sites_enabled"] | default(false) %}
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

create /etc/nginx/sites-available/{{ pillar["keep"]["host"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["keep"]["host"] }}.conf
    - contents: |
        map $http_upgrade $connection_upgrade_keepalive {
            default upgrade;
            ''      '';
        }
        upstream keep-front{
          server 127.0.0.1:3000;
          keepalive 10;
        }
        upstream keep-api{
          server 127.0.0.1:8080;
          keepalive 10;
        }
        server {
          listen 80;
          server_name {{ pillar["keep"]["host"] }};
          return 301 https://$host$request_uri;
        }
        server {
          listen 443 ssl;
          server_name {{ pillar["keep"]["host"] }};
          ssl_certificate /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_key.key;
          location = /robots.txt {
            return 200 "User-agent: *\nDisallow: /\n";
          }
          location / {
            proxy_pass http://keep-front;
            proxy_http_version 1.1;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header Upgrade           $http_upgrade;
            proxy_set_header Connection        $connection_upgrade_keepalive;
          }
        }
        server {
          listen 8443 ssl;
          server_name {{ pillar["keep"]["host"] }};
          ssl_certificate /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_key.key;
          location = /robots.txt {
            return 200 "User-agent: *\nDisallow: /\n";
          }
          location / {
            proxy_pass http://keep-api;
            proxy_http_version 1.1;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header Upgrade           $http_upgrade;
            proxy_set_header Connection        $connection_upgrade_keepalive;
          }
        }

create symlink /etc/nginx/sites-enabled/{{ pillar["keep"]["host"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["keep"]["host"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["keep"]["host"] }}.conf
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
          map $http_upgrade $connection_upgrade_keepalive {
              default upgrade;
              ''      '';
          }
          upstream keep-front{
            server 127.0.0.1:3000;
            keepalive 10;
          }
          upstream keep-api{
            server 127.0.0.1:8080;
            keepalive 10;
          }
          server {
            listen 80;
            server_name {{ pillar["keep"]["host"] }};
            return 301 https://$host$request_uri;
          }
          server {
            listen 443 ssl;
            server_name {{ pillar["keep"]["host"] }};
            ssl_certificate /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_key.key;
            location = /robots.txt {
              return 200 "User-agent: *\nDisallow: /\n";
            }
            location / {
              proxy_pass http://keep-front;
              proxy_http_version 1.1;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
              proxy_set_header Host              $host;
              proxy_set_header X-Real-IP         $remote_addr;
              proxy_set_header Upgrade           $http_upgrade;
              proxy_set_header Connection        $connection_upgrade_keepalive;
            }
          }
          server {
            listen 8443 ssl;
            server_name {{ pillar["keep"]["host"] }};
            ssl_certificate /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/keep_{{ pillar["keep"]["host"] }}_key.key;
            location = /robots.txt {
              return 200 "User-agent: *\nDisallow: /\n";
            }
            location / {
              proxy_pass http://keep-api;
              proxy_http_version 1.1;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
              proxy_set_header Host              $host;
              proxy_set_header X-Real-IP         $remote_addr;
              proxy_set_header Upgrade           $http_upgrade;
              proxy_set_header Connection        $connection_upgrade_keepalive;
            }
          }
        }
  {%- endif %}

  {{ verify_and_issue(acme, "keep", pillar["keep"]["host"]) }}

keep_data_dirs:
  file.directory:
    - names:
      - {{ pillar["keep"]["homedir"] }}/state
    - user: 999
    - group: 999
    - makedirs: True

docker_network:
  docker_network.present:
    - name: keephq_default

{% for component in pillar["keep"]["components"] %}
{{ component["name"] }}_image:
  cmd.run:
    - name: docker pull {{ component["image"] }}

{{ component["name"] }}_container:
  docker_container.running:
    - name: keephq-{{ component["name"] }}-1
    - image: {{ component["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    {% if 'volumes' in component %}
    - binds:
      {% for bind in component["volumes"] %}
      - {{ bind }}
      {%- endfor %}
    {%- endif %}
    {% if 'ports' in component %}
    - publish:
      {% for port in component["ports"] %}
      - {{ port }}
      {%- endfor %}
    {%- endif %}
    - networks:
      - keephq_default:
        - aliases:
          - {{ component["name"] }}
    {% if 'environment' in component %}
    - environment:
      {% for key_val in component["environment"] %}
      - {{ key_val }}
      {%- endfor %}
    {%- endif %}
{% endfor %}

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


