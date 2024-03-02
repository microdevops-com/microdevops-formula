{% if pillar["metabase"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["metabase"]["docker-ce_version"], "daemon_json": '{"iptables": false}'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["metabase"]["separated_nginx_config"] is defined and pillar["metabase"]["separated_nginx_config"] %}
nginx_separated_config:

  file.managed:
    - name: /etc/nginx/sites-available/metabase.conf
    {%- if pillar["metabase"]["custom_separated_nginx_config"] is defined %}
    - contents_pillar: metabase:custom_separated_nginx_config
    {%- else %}
    - contents: |
        server {
            listen 80;
            return 301 https://$host$request_uri;
        }
      {%- for domain in pillar["metabase"]["domains"] %}
        server {
            listen 443 ssl;
            server_name {{ domain["name"] }};
            root /opt/metabase/{{ domain["name"] }};
            index index.html;
            ssl_certificate /opt/acme/cert/metabase_{{ domain["name"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/metabase_{{ domain["name"] }}_key.key;
        {%- for instance in domain["instances"] %}
            location /{{ instance["name"] }}/ {
                proxy_connect_timeout 300;
                proxy_read_timeout 300;
                proxy_send_timeout 300;
                proxy_buffering off;
                proxy_pass http://localhost:{{ instance["port"] }}/;
            }
        {%- endfor %}
        }
      {%- endfor %}
    {%- endif %}

nginx_separated_config_link:
  file.symlink:
    - name: /etc/nginx/sites-enabled/metabase.conf
    - target: /etc/nginx/sites-available/metabase.conf

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
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
    {%- for domain in pillar["metabase"]["domains"] %}
            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                root /opt/metabase/{{ domain["name"] }};
                index index.html;
                ssl_certificate /opt/acme/cert/metabase_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/metabase_{{ domain["name"] }}_key.key;
      {%- for instance in domain["instances"] %}
                location /{{ instance["name"] }}/ {
                    proxy_connect_timeout 300;
                    proxy_read_timeout 300;
                    proxy_send_timeout 300;
                    proxy_buffering off;
                    proxy_pass http://localhost:{{ instance["port"] }}/;
                }
      {%- endfor %}
            }
    {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- endif %}

  {%- for domain in pillar["metabase"]["domains"] %}

    {%- if "acme_account" in domain %}

      {{ verify_and_issue(domain["acme_account"], "metabase", domain["name"]) }}

    {%- endif %}
    
    {%- set i_loop = loop %}
    {%- for instance in domain["instances"] %}
metabase_etc_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/metabase/{{ domain["name"] }}/{{ instance["name"] }}/plugins
    - mode: 755
    - makedirs: True

    {%- if instance["plugins"] is defined and "clickhouse" in instance["plugins"] %}
metabase_download_clickhouse_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/metabase/{{ domain["name"] }}/{{ instance["name"] }}/plugins/clickhouse.metabase-driver.jar
    - source: https://github.com/enqueue/metabase-clickhouse-driver/releases/download/{{ instance["plugins"]["clickhouse"] }}/clickhouse.metabase-driver.jar
    - skip_verify: True
    - user: 2000
    - group: 2000
    - mode: 644

    {%- endif %}

metabase_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance["image"] }}

metabase_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: metabase-{{ domain["name"] }}-{{ instance["name"] }}
    - user: root
    - image: {{ instance["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    {%- if instance["plugins"] is defined %}
    - binds:
      {%- if "clickhouse" in instance["plugins"] %}
        - /opt/metabase/{{ domain["name"] }}/{{ instance["name"] }}/plugins/clickhouse.metabase-driver.jar:/plugins/clickhouse.metabase-driver.jar
      {%- endif %}
    {%- endif %}
    - publish:
        - 127.0.0.1:{{ instance["port"] }}:3000/tcp
    - environment:
        - MB_DB_TYPE: {{ instance["db"]["type"] }}
        - MB_DB_HOST: {{ instance["db"]["host"] }}
        - MB_DB_PORT: {{ instance["db"]["port"] }}
        - MB_DB_DBNAME: {{ instance["db"]["dbname"] }}
        - MB_DB_USER: {{ instance["db"]["user"] }}
        - MB_DB_PASS: {{ instance["db"]["pass"] }}
        - JAVA_TIMEZONE: {{ instance["java_timezone"] }}
        - MB_SITE_URL: https://{{ domain["name"] }}/{{ instance["name"] }}/

    {%- endfor %}
  {%- endfor %}

  {%- for domain in pillar["metabase"]["domains"] %}
nginx_domain_index_{{ loop.index }}:
  file.managed:
    - name: /opt/metabase/{{ domain["name"] }}/index.html
    - contents: |
    {%- if 'default_instance' in domain %}
        <meta http-equiv="refresh" content="0; url='https://{{ domain["name"] }}/{{ domain["default_instance"] }}'" />
    {%- else %}
      {%- for instance in domain["instances"] %}
        <a href="{{ instance["name"] }}/">{{ instance["name"] }}</a><br>
      {%- endfor %}
    {%- endif %}
  {%- endfor %}

nginx_reload:
  cmd.run:
    - runas: root
    - name: "/usr/sbin/nginx -t -q && /usr/sbin/nginx -s reload"

nginx_reload_cron:
  cron.present:
    - name: "/usr/sbin/nginx -t -q && /usr/sbin/nginx -s reload"
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

{% endif %}
