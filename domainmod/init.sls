{% if pillar["domainmod"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["domainmod"]["nginx_sites_enabled"] | default(false) %}
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
    {%- for domain in pillar["domainmod"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
        {%- if pillar["domainmod"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ domain["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
        upstream {{ domain["name"] | replace(".","_") }} {
          server 127.0.0.1:{{ domain["internal_port"] }};
        }
        server {
          listen {{ pillar["domainmod"]["external_port"] | default(443) }} ssl;
          server_name {{ domain["name"] }};
          ssl_certificate /opt/acme/cert/domainmod_{{ domain["name"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/domainmod_{{ domain["name"] }}_key.key;
          location = /robots.txt {
            return 200 "User-agent: *\nDisallow: /\n";
          }
          location / {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $http_host;

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
      {%- if pillar["domainmod"]["external_port"] is not defined %}
          server {
            listen 80;
            return 301 https://$host$request_uri;
          }
      {%- endif %}
      {%- for domain in pillar["domainmod"]["domains"] %}
          upstream {{ domain["name"] | replace(".","_") }} {
            server 127.0.0.1:{{ domain["internal_port"] }};
          }
          server {
            listen {{ pillar["domainmod"]["external_port"] | default(443) }} ssl;
            server_name {{ domain["name"] }};
            ssl_certificate /opt/acme/cert/domainmod_{{ domain["name"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/domainmod_{{ domain["name"] }}_key.key;
            location = /robots.txt {
              return 200 "User-agent: *\nDisallow: /\n";
            }
            location / {
              proxy_pass http://{{ domain["name"] | replace(".","_") }};
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Host $http_host;
            }
          }
    {%- endfor %}
        }
  {%- endif %}
delete /etc/nginx/sites-enabled/default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["domainmod"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh domainmod {{ domain["name"] }}"

domainmod_data_dir_{{ loop.index }}:
  file.directory:
    - names:
      - /opt/domainmod/{{ domain["name"] }}/data/
    - user: {{ domain["env_vars"]["PUID"] }}
    - group: {{ domain["env_vars"]["PGID"] }}
    - makedirs: True
domainmod_backup_dir_{{ loop.index }}:
  file.directory:
    - names:
      - /opt/domainmod/{{ domain["name"] }}/data/temp/
    - user: 33
    - group: 33

domainmod_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

domainmod_container_{{ loop.index }}:
  docker_container.running:
    - name: domainmod-{{ domain["name"] }}
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: always
    - binds:
      - /opt/domainmod/{{ domain["name"] }}/data:/var/www/html
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:80/tcp
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
