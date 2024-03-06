{% if pillar["snipe-it"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["snipe-it"]["docker-ce_version"],
                         "daemon_json": '{ "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

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
            use epoll;
            multi_accept on;
        }
        http {
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
  {%- for domain in pillar["snipe-it"]["domains"] %}
            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                ssl_certificate /opt/acme/cert/snipe-it_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/snipe-it_{{ domain["name"] }}_key.key;
                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }}/;
                    include    proxy_params;
                    proxy_set_header X-Forwarded-Proto $scheme;
                }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["snipe-it"]["domains"] %}

    {{ verify_and_issue(domain["acme_account"], "snipe-it", domain["name"]) }}

snipe-it_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/snipe-it/{{ domain["name"] }}/data/var/lib/snipeit/
    - mode: 755
    - makedirs: True

snipe-it_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

snipe-it_container_{{ loop.index }}:
  docker_container.running:
    - name: snipe-it-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:80/tcp
    - binds:
        - /opt/snipe-it/{{ domain["name"] }}/data/var/lib/snipeit:/var/lib/snipeit:rw
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
