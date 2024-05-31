{% if pillar["sentry"] is defined and "version" in pillar["sentry"]  %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {{ verify_and_issue(pillar["sentry"]["acme_account"], "sentry", pillar["sentry"]["acme_domain"]) }}

  {%- if pillar["sentry"]["config"]["web"].get("install_nginx", True) %}
sentry_install_nginx:
  pkg.installed:
    - pkgs:
      - nginx-full
  {% endif %}

sentry_nginx_files_1:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["sentry"]["config"]["web"]["nginx_conf_path"] | default(pillar["sentry"]["acme_domain"]) }}.conf
    - contents: |
        set_real_ip_from 127.0.0.1;
        set_real_ip_from 172.16.0.0/16;
        real_ip_header X-Forwarded-For;
        real_ip_recursive on;
        server {
            listen 80;
            server_name {{ pillar["sentry"]["acme_domain"] }};
            location / {
                if ($request_method = GET) {
                  rewrite  ^ https://$host$request_uri? permanent;
                }
                return 405;
            }
        }
        server {
            listen 443 ssl;
            server_name {{ pillar["sentry"]["acme_domain"] }};
            ssl_certificate /opt/acme/cert/sentry_{{ pillar["sentry"]["acme_domain"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/sentry_{{ pillar["sentry"]["acme_domain"] }}_key.key;
            ssl_ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS;
            ssl_session_cache shared:SSL:128m;
            ssl_session_timeout 10m;
            proxy_redirect off;
            # keepalive + raven.js is a disaster
            keepalive_timeout 0;
            # use very aggressive timeouts
            proxy_read_timeout 5s;
            proxy_send_timeout 5s;
            send_timeout 5s;
            resolver_timeout 5s;
            client_body_timeout 5s;
            # buffer larger messages
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
  {% if pillar["sentry"]["config"]["web"]["nginx_conf_path"] is not defined %}
sentry_nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

sentry_nginx_files_3:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["sentry"]["acme_domain"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["sentry"]["acme_domain"] }}.conf
  {% endif %}
sentry_installer_clone_fom_git:
  git.latest:
    - name: https://github.com/getsentry/self-hosted.git
    - target: /opt/sentry/
    - rev: {{ pillar ["sentry"]["version"] }}
    - force_reset: True

sentry_config_1:
  file.managed:
    - name: /opt/sentry/sentry/config.yml
    - mode: 0644
    - source: salt://sentry/files/config.yml
    - template: jinja

# sentry.conf.py best doc is here: https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
sentry_config_2:
  file.managed:
    - name: /opt/sentry/sentry/sentry.conf.py
    - mode: 0644
    - source: salt://sentry/files/sentry.conf.py
    - template: jinja

sentry_create_env_custom:
  file.copy:
    - name: /opt/sentry/.env.custom
    - source: /opt/sentry/.env
    - force: true

sentry_custom_env:
  file.replace:
    - name: /opt/sentry/.env.custom
    - pattern: '^ *SENTRY_EVENT_RETENTION_DAYS=.*$'
    - repl: 'SENTRY_EVENT_RETENTION_DAYS={{ salt["pillar.get"]("sentry:config:general:options:system:event_retention_days", 90) }}'
    - append_if_not_found: True
    - ignore_if_missing: True

  {%- if "enhance_image_sh" in pillar["sentry"] %}
sentry_enhance-image_sh_create:
  file.managed:
    - name: /opt/sentry/sentry/enhance-image.sh
    - contents: {{ pillar["sentry"]["enhance_image_sh"] | yaml_encode }}
    - mode: 755

  {%- else %}
sentry_enhance-image_sh_del:
  file.absent:
    - name: /opt/sentry/sentry/enhance-image.sh

  {%- endif %}

sentry_install:
  cmd.run:
    # For versions older than 22.10.0
    # - name: ./install.sh --no-user-prompt --skip-commit-check
    - name: ./install.sh --skip-user-creation --skip-commit-check --no-report-self-hosted-issues
    - shell: /bin/bash
    - cwd: /opt/sentry
    - onchanges:
      - file: /opt/sentry/sentry/config.yml
      - file: /opt/sentry/sentry/sentry.conf.py
      - git: https://github.com/getsentry/self-hosted.git
    - require:
      - cmd: sentry_acme_run

sentry_backup_dir:
  file.directory:
    - name: /opt/sentry/backup

sentry_export_backup_script:
  file.managed:
    - name: /opt/sentry/backup_export.sh
    - source: salt://sentry/files/backup_export.sh
    - mode: 775

sentry_volume_backup_script:
  file.managed:
    - name: /opt/sentry/backup_volumes.sh
    - source: salt://sentry/files/backup_volumes.sh
    - mode: 775

sentry_volume_restore_script:
  file.managed:
    - name: /opt/sentry/restore_volumes.sh
    - source: salt://sentry/files/restore_volumes.sh
    - mode: 775

sentry_docker_compose_up:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/sentry
    - name: |
        [[ -f /opt/sentry/.env.custom ]] && docker-compose --env-file /opt/sentry/.env.custom up -d || docker-compose up -d
    - require:
      - cmd: sentry_acme_run

sentry_superuser:
  cmd.run:
    - name: docker exec sentry-self-hosted-web-1 sentry createuser --email {{ pillar["sentry"]["admin_email"] }} --password {{ pillar["sentry"]["admin_password"] }} --superuser --staff --force-update --no-input
    - require:
      - cmd: sentry_acme_run

sentry_fix_sentry_admin_permissions:
  cmd.run:
    - name: docker exec sentry-self-hosted-web-1 sentry permissions add -u "{{ pillar["sentry"]["admin_email"] }}" -p "users.admin"
    - require:
      - cmd: sentry_acme_run

  {%- if "organization_creation_rate_limit_to_0" in pillar["sentry"] and pillar["sentry"]["organization_creation_rate_limit_to_0"] %}
sentry_organization_creation_rate_limit_to_0:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          INSERT INTO sentry_option
            (key, value, last_updated)
          VALUES
            (
              'api.rate-limit.org-create',
              'gAJLAC4=',
              now()
            )
          ON CONFLICT (key) DO UPDATE SET value = 'gAJLAC4=', last_updated = now();
        \""
    - require:
      - cmd: sentry_acme_run
  {%- endif %}

  {% if pillar["sentry"]["config"]["web"]["nginx_conf_path"] is not defined %}

sentry_nginx_reload:
  cmd.run:
    - name: service nginx configtest && service nginx reload

sentry_nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

   {% endif %}
{%- endif %}
