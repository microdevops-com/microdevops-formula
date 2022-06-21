{% if pillar['sentry'] is defined  %}
install_nginx:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["sentry"]["acme_domain"] }}.conf
    - contents: |
        server {
            listen 80;
            server_name {{ pillar["sentry"]["acme_domain"] }};
            return 301 https://$host$request_uri;
        }
        server {
            listen 443 ssl;
            server_name {{ pillar["sentry"]["acme_domain"] }};
            ssl_certificate /opt/acme/cert/sentry_{{ pillar["sentry"]["acme_domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/sentry_{{ pillar["sentry"]["acme_domain"] }}_key.key;
            proxy_redirect off;
            keepalive_timeout 0;
            proxy_read_timeout 5s;
            proxy_send_timeout 5s;
            send_timeout 5s;
            resolver_timeout 5s;
            client_body_timeout 5s;
            client_max_body_size 5m;
            client_body_buffer_size 100k;
            location / {
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $remote_addr;
                proxy_set_header Host $http_host;
                proxy_pass http://localhost:9000/;
                add_header Strict-Transport-Security "max-age=31536000";
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["sentry"]["acme_domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["sentry"]["acme_domain"] }}.conf

nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["sentry"]["acme_account"] }}/verify_and_issue.sh sentry {{ pillar["sentry"]["acme_domain"] }}"

sentry_installer_clone_fom_git:
  git.latest:
    - name: https://github.com/getsentry/self-hosted.git
    - target: /opt/sentry/
    - rev: {{ pillar ["sentry"]["version"] }}

sentry_config_1:
  file.managed:
    - name: '/opt/sentry/sentry/config.yml'
    - mode: '0644'
    - source: 'salt://sentry/files/config.yml'
    - template: jinja

{# sentry.conf.py best doc is here: https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py #}
sentry_config_2:
  file.managed:
    - name: '/opt/sentry/sentry/sentry.conf.py'
    - mode: '0644'
    - source: 'salt://sentry/files/sentry.conf.py'
    - template: jinja

sentry_install:
  cmd.run:
    - name: ./install.sh --no-user-prompt --skip-commit-check
    - shell: /bin/bash
    - cwd: /opt/sentry
    - onchanges:
      - file: /opt/sentry/sentry/config.yml
      - file: /opt/sentry/sentry/sentry.conf.py
      - git: https://github.com/getsentry/self-hosted.git

  {% if pillar['sentry']['secret'] is not defined or pillar['sentry']['secret'] is none %}
sentry_secret_generation:
  cmd.run:
    - name: docker-compose run --rm web config generate-secret-key 2>/dev/null
    - shell: /bin/bash
    - cwd: /opt/sentry
  {% else %}
sentry_docker_compose_up:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/sentry
    - name: docker-compose up -d

sentry_superuser:
  cmd.run:
    - name: docker exec sentry-self-hosted-postgres-1 bash -c "( echo \"select id from auth_user where email = '{{ pillar['sentry']['admin_email'] }}' and is_superuser is true\" | su -l postgres -c \"psql postgres\" | grep -q \"(0 rows)\" )" && docker exec sentry-self-hosted-web-1 bash -c "sentry createuser --email '{{ pillar['sentry']['admin_email'] }}' --password '{{ pillar['sentry']['admin_password'] }}' --superuser --no-input" || true
    - runas: 'root'

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
  {%- endif %}
{%- endif %}
