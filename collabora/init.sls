{% if pillar["collabora"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

  {% from "acme/macros.jinja" import verify_and_issue %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
  {%- if pillar["collabora"]["nginx_sites_enabled"] | default(false) %}
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
    {% if pillar["collabora"]["full"] | default(false) %}
create /etc/nginx/sites-available/{{ pillar["collabora"]["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["collabora"]["name"] }}.conf
    - contents: |
        {%- if pillar["collabora"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ pillar["collabora"]["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
        upstream {{ pillar["collabora"]["name"] | replace(".","_") }} {
          server 127.0.0.1:{{ pillar["collabora"]["internal_port"] | default('9980') }};
        }
        server {
          listen 443 ssl;
          server_name {{ pillar["collabora"]["name"] }};
          ssl_certificate /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_key.key;
          # static files
          location ^~ /browser {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # WOPI discovery URL
          location ^~ /hosting/discovery {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Capabilities
          location ^~ /hosting/capabilities {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # main websocket
          location ~ ^/cool/(.*)/ws$ {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
          # download, presentation and image upload
          location ~ ^/(c|l)ool {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Admin Console websocket
          location ^~ /cool/adminws {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
        }

create symlink /etc/nginx/sites-enabled/{{ pillar["collabora"]["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["collabora"]["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["collabora"]["name"] }}.conf
    - force: True

    {% else %}

      {%- for domain in pillar["collabora"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
        {%- if pillar["collabora"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ domain["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
        upstream {{ domain["name"] | replace(".","_") }} {
          server 127.0.0.1:{{ domain["internal_port"] | default('9980') }};
        }
        server {
          listen 443 ssl;
          server_name {{ domain["name"] }};
          ssl_certificate /opt/acme/cert/collabora_{{ domain["name"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/collabora_{{ domain["name"] }}_key.key;
          # static files
          location ^~ /browser {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # WOPI discovery URL
          location ^~ /hosting/discovery {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Capabilities
          location ^~ /hosting/capabilities {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # main websocket
          location ~ ^/cool/(.*)/ws$ {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
          # download, presentation and image upload
          location ~ ^/(c|l)ool {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Admin Console websocket
          location ^~ /cool/adminws {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
        }

create symlink /etc/nginx/sites-enabled/{{ domain["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ domain["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - force: True
      {%- endfor %}

    {%- endif %}

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
            server {
              listen 80;
              return 301 https://$host$request_uri;
            }
    {% if pillar["collabora"]["full"] | default(false) %}
            upstream {{ pillar["collabora"]["name"] | replace(".","_") }} {
              server 127.0.0.1:{{ pillar["collabora"]["internal_port"] | default('9980') }};
            }
            server {
              listen 443 ssl;
              server_name {{ pillar["collabora"]["name"] }};
              ssl_certificate /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_fullchain.cer;
              ssl_certificate_key /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_key.key;
              # static files
              location ^~ /browser {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # WOPI discovery URL
              location ^~ /hosting/discovery {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Capabilities
              location ^~ /hosting/capabilities {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # main websocket
              location ~ ^/cool/(.*)/ws$ {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
              # download, presentation and image upload
              location ~ ^/(c|l)ool {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Admin Console websocket
              location ^~ /cool/adminws {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
            }
    {% else %}
      {%- for domain in pillar["collabora"]["domains"] %}
            upstream {{ domain["name"] | replace(".","_") }} {
              server 127.0.0.1:{{ domain["internal_port"] | default('9980') }};
            }
            server {
              listen 443 ssl;
              server_name {{ domain["name"] }};
              ssl_certificate /opt/acme/cert/collabora_{{ domain["name"] }}_fullchain.cer;
              ssl_certificate_key /opt/acme/cert/collabora_{{ domain["name"] }}_key.key;
              # static files
              location ^~ /browser {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # WOPI discovery URL
              location ^~ /hosting/discovery {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Capabilities
              location ^~ /hosting/capabilities {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # main websocket
              location ~ ^/cool/(.*)/ws$ {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
              # download, presentation and image upload
              location ~ ^/(c|l)ool {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Admin Console websocket
              location ^~ /cool/adminws {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
            }
      {%- endfor %}
    {%- endif %}
        }
  {%- endif %}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default


  {% if pillar["collabora"]["full"] | default(false) %}

    {{ verify_and_issue(acme, "collabora", pillar["collabora"]["name"]) }}

download_collaboraonline-release-keyring.gpg:
  file.managed:
    - name: /usr/share/keyrings/collaboraonline-release-keyring.gpg
    - source: https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg
    - skip_verify: True

apt_sources_list.d_collabora.list:
  file.managed:
    - name: /etc/apt/sources.list.d/collaboraonline.sources
    - contents: |
        Types: deb
        URIs: https://www.collaboraoffice.com/repos/CollaboraOnline/24.04/customer-deb-{{ pillar["collabora"]["customer_hash"] }}
        Suites: ./
        Signed-By: /usr/share/keyrings/collaboraonline-release-keyring.gpg

apt_update:
  cmd.run:
    - name: apt update

colabora_install:
  pkg.latest:
    - pkgs:
      - coolwsd
      - nextcloud-office-brand

collabora_config:
  file.managed:
    - name: /etc/coolwsd/coolwsd.xml
    - mode: 660
    - user: cool
    - group: cool
    - source: {{ pillar['collabora']['coolwsd_xml']['template'] | default('salt://collabora/files/coolwsd.xml.jinja') }}
    - template: jinja
    - makedirs: True
    - context: {{ pillar['collabora']['coolwsd_xml']['values'] }}
    - defaults:
        # generate new random password if not set in pillar
        password: {{ salt['random.get_str'](16, chars='-_@abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ123456789') }}

collabora_systemd_service:
  service.running:
    - name: coolwsd
    - enable: True

collabora_systemd_restart:
  cmd.run:
    - name: systemctl restart coolwsd
    - onchanges:
      - file: /etc/coolwsd/coolwsd.xml

  {% else %}

    {%- for domain in pillar["collabora"]["domains"] %}

      {{ verify_and_issue(acme, "collabora", domain["name"]) }}

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

  {%- endif %}

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
