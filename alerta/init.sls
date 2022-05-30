{% if pillar["alerta"] is defined %}

  {%- set pyenv_version = "3.7.8" %}

alerta_reqs_install:
  pkg.installed:
    - pkgs:
      - libpcre3
      - libpcre3-dev
      - nginx

alerta_group:
  group.present:
    - name: alerta

alerta_user:
  user.present:
    - name: alerta
    - gid: alerta
    - home: /opt/alerta/alerta
    - createhome: True
    - password: '!'
    - shell: /bin/bash
    - fullname: alerta

alerta_nginx_root_dir:
  file.directory:
    - name: /opt/alerta/alerta/html
    - user: alerta
    - group: alerta
    - mode: 0755
    - makedirs: True

alerta_git_checkout:
  git.latest:
    - name: https://github.com/alerta/alerta
    - rev: {{ pillar["alerta"]["version"] }}
    - target: /opt/alerta/alerta/src
    - branch: master
    - force_reset: True
    - force_fetch: True
    - user: alerta

alerta_virtualenv_dir:
  file.directory:
    - name: /opt/alerta/alerta/venv
    - user: alerta
    - group: alerta
    - mode: 0755
    - makedirs: True

alerta_virtualenv_python_version:
  file.managed:
    - name: /opt/alerta/alerta/venv/.python-version
    - user: alerta
    - group: alerta
    - mode: 0644
    - contents:
      - {{ pyenv_version }}

alerta_virtualenv_pip:
  cmd.run:
    - cwd: /tmp
    - env:
        PYENV_VERSION: {{ pyenv_version }}
    - name: /usr/local/pyenv/shims/pip install virtualenv

alerta_virtualenv_bin:
  file.managed:
    - name: /opt/alerta/alerta/virtualenv-{{ pyenv_version }}
    - user: alerta
    - group: alerta
    - mode: 0755
    - contents: |
        #!/bin/sh
        export PYENV_VERSION='{{ pyenv_version }}'
        /usr/local/pyenv/shims/virtualenv "$@"

alerta_virtualenv:
  virtualenv.managed:
    - name: /opt/alerta/alerta/venv
    - python: /usr/local/pyenv/shims/python
    - user: alerta
    - system_site_packages: False
    - venv_bin: /opt/alerta/alerta/virtualenv-{{ pyenv_version }}
    - env_vars:
        PYENV_VERSION: {{ pyenv_version }}

alerta_setup_script_run:
  cmd.run:
    - cwd: /opt/alerta/alerta/src
    - runas: alerta
    - name: |
        ~/venv/bin/pip install --upgrade uwsgi -I --no-cache-dir; ~/venv/bin/pip install --upgrade alerta-server alerta; ~/venv/bin/pip install --upgrade -r requirements.txt

alerta_telegram_setup_script_run:
  cmd.run:
    - cwd: /opt/alerta/alerta/src
    - runas: alerta
    - name: |
        ~/venv/bin/pip install --upgrade git+https://github.com/sysadmws/alerta-telegram.git

alerta_telegram_template:
  file.managed:
    - name: /opt/alerta/alerta/telegram_template.jinja
    - user: alerta
    - group: alerta
    - mode: 0644
    - contents_pillar: alerta:telegram_template

alerta_uwsgi_dir:
  file.directory:
    - name: /opt/alerta/alerta/uwsgi
    - user: alerta
    - group: alerta
    - makedirs: True

alerta_uwsgi_wsgi_py:
  file.managed:
    - name: /opt/alerta/alerta/uwsgi/wsgi.py
    - user: alerta
    - group: alerta
    - mode: 0644
    - contents: |
        from alerta import create_app
        app = create_app()

alerta_uwsgi_sites_dir:
  file.directory:
    - name: /etc/uwsgi/sites
    - user: root
    - group: root
    - makedirs: True

alerta_uwsgi_ini:
  file.managed:
    - name: /etc/uwsgi/sites/alerta.ini
    - user: root
    - group: root
    - mode: 0644
    - source: salt://alerta/files/uwsgi.ini
    - replace: True
    - template: jinja
    - defaults:
        base_url: "https://{{ pillar["alerta"]["domain"] }}/api"
        processes: {{ pillar["alerta"]["uwsgi"]["processes"] }}
        listen: {{ pillar["alerta"]["uwsgi"]["listen"] }}

alerta_uwsgi_service:
  file.managed:
    - name: /etc/systemd/system/uwsgi-alerta.service
    - user: root
    - group: root
    - source: salt://alerta/files/uwsgi.service
    - replace: True

alerta_config:
  file.managed:
    - name: /opt/alerta/alerta/alertad.conf
    - user: alerta
    - group: alerta
    - source: salt://alerta/files/alertad.conf
    - replace: True
    - template: jinja
    - defaults:
        base_url: "https://{{ pillar["alerta"]["domain"] }}/api"
        secret_key: {{ pillar["alerta"]["secret_key"] }}
        db_user: {{ pillar["alerta"]["db"]["user"] }}
        db_pass: {{ pillar["alerta"]["db"]["pass"] }}
        db_host: {{ pillar["alerta"]["db"]["host"] }}
        db_name: {{ pillar["alerta"]["db"]["name"] }}
        config: {{ pillar["alerta"]["config"] | yaml_encode }}

alerta_cli_config:
  file.managed:
    - name: /opt/alerta/alerta/.alerta.conf
    - user: alerta
    - group: alerta
    - mode: 0644
    - contents: |
        [DEFAULT]
        endpoint = https://{{ pillar["alerta"]["domain"] }}/api
        key = {{ pillar["alerta"]["cli_key"] }}

alerta_reload:
  cmd.run:
    - runas: root
    - name: systemctl daemon-reload && systemctl restart uwsgi-alerta && systemctl enable uwsgi-alerta && systemctl is-active uwsgi-alerta

alerta_housekeeping_cron:
  cron.present:
    # otherwise it will swipe out closed (green) after default 2 hours and info after 12 hours
    - name: /opt/alerta/alerta/venv/bin/alerta housekeeping --expired 24 --info 24
    - identifier: alerta_housekeeping
    - user: alerta
    - minute: '*'

alerta_hb_cron:
  cron.present:
    - name: /opt/alerta/alerta/venv/bin/alerta heartbeats --alert --severity major
    - identifier: alerta_heartbeats_alert
    - user: alerta
    - minute: '*'

alerta_install_webui_archive:
  archive.extracted:
    - name: /opt/alerta/alerta/html
    - source: {{ pillar["alerta"]["webui_source"] }}
    - user: alerta
    - group: alerta
    - enforce_toplevel: False

alerta_install_webui_config:
  file.managed:
    - name: /opt/alerta/alerta/html/config.json
    - user: alerta
    - group: alerta
    - mode: 0644
    - contents: |
        {"endpoint": "https://{{ pillar['alerta']['domain'] }}/api"}

alerta_main_nginx:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        user www-data;
        worker_processes auto;

        events {
            worker_connections 512;
        }

        http {
            include /etc/nginx/mime.types;
            default_type  application/octet-stream;

            sendfile on;
            keepalive_timeout 65;
            server_tokens off;

            gzip on;
            gzip_disable "msie6";
            gzip_vary on;
            gzip_proxied any;
            gzip_comp_level 6;
            gzip_buffers 16 8k;
            gzip_http_version 1.1;
            gzip_min_length 256;
            gzip_types text/plain text/css application/json application/x-javascript application/javascript text/xml application/xml application/xml+rss text/javascript application/vnd.ms-fontobject application/x-font-ttf font/opentype image/svg+xml image/x-icon;

            server {
                listen 443 ssl http2;
                server_name {{ pillar["alerta"]["domain"] }};

                include snippets/ssl-params.conf;

                ssl_certificate /opt/acme/cert/alerta_{{ pillar["alerta"]["domain"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/alerta_{{ pillar["alerta"]["domain"] }}_key.key;

                root /opt/alerta/alerta/html;
                index index.html;
                charset UTF-8;
                autoindex off;

                error_page 403 =404;

                access_log /var/log/nginx/alerta.access.log;
                error_log /var/log/nginx/alerta.error.log;

                client_max_body_size 4M;
                client_body_buffer_size 128k;

                location / {
                    try_files $uri $uri/ /index.html;
                }

                location = /robots.txt  { access_log off; log_not_found off; }
                location = /favicon.ico { access_log off; log_not_found off; }
                location ~ /\.          { access_log off; log_not_found off; deny all; }
                location ~ ~$           { access_log off; log_not_found off; deny all; }

                location ~* ^.+\.(jpg|jpeg|gif|png|ico|css|zip|tgz|gz|rar|bz2|pdf|txt|tar|wav|bmp|rtf|js|flv|swf|svg|woff|woff2|eot)$ {
                    expires max;
                    access_log off;
                    log_not_found off;
                }

                location ~ /api {
                    include uwsgi_params;
                    uwsgi_pass unix:/tmp/uwsgi-alerta.sock;
                    proxy_set_header Host $host:$server_port;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                }
            }
        }

alerta_nginx_absent_default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

alerta_acme_run:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["alerta"]["acme_account"] }}/verify_and_issue.sh alerta {{ pillar["alerta"]["domain"] }}"

alerta_nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx restart

alerta_nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx restart
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

  {%- if "customers" in pillar["alerta"] %}
    {%- for customer in pillar["alerta"]["customers"] %}
alerta_customer_{{ loop.index }}:
  cmd.run:
    - name: |
        echo "INSERT INTO customers (id, match, customer) VALUES ('{{ customer["id"] }}', '{{ customer["match"] }}', '{{ customer["customer"] }}') ON CONFLICT (id) DO UPDATE SET match = '{{ customer["match"] }}', customer = '{{ customer["customer"] }}';" | su -l postgres -c "psql alerta" | grep "INSERT"

    {%- endfor %}
  {%- endif %}

  {%- if "keys" in pillar["alerta"] %}
    {%- for key in pillar["alerta"]["keys"] %}
      {%- if "customer" in key %}
        {%- set key_customer = "'" ~ key["customer"] ~ "'" %}
      {%- else %}
        {%- set key_customer = "NULL" %}
      {%- endif %}
alerta_key_{{ loop.index }}:
  cmd.run:
    - name: |
        echo "INSERT INTO keys (id, key, \"user\", scopes, text, expire_time, count, customer) VALUES ('{{ key["id"] }}', '{{ key["key"] }}', 'root', '{{ key["scopes"] }}', '{{ key["text"] }}', now() + interval '100 years', 0, {{ key_customer }}) ON CONFLICT (id) DO UPDATE SET key = '{{ key["key"] }}', \"user\" = 'root', scopes = '{{ key["scopes"] }}', text = '{{ key["text"] }}', expire_time = now() + interval '100 years', customer = {{ key_customer }};" | su -l postgres -c "psql alerta" | grep "INSERT"

    {%- endfor %}
  {%- endif %}

{% endif %}
